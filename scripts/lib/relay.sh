#!/usr/bin/env bash
# relay <主机> check|docker|images|launcher-key（docs/57）
# 让 Launcher 管理界面能把 Domestic 包（中继 mx-domestic、边缘、DNS、443 的 HTTPS）推到测试中继上：
# 那个包要目标机有 docker、有两个镜像、认 Launcher 的 SSH 公钥。这几样由推送机（s2）经 L2 的边缘工具
# （qp-tunnel-cli edge ssh，用 /var/lib/qp-tunnel/edge 的密钥）准备好。镜像在 s2 上经代理拉，再推过去：
# 数据从内往外推（CLAUDE.md），domestic02 自己不用连 Docker Hub。
# 只给测试中继用：生产的 Domestic（inventory 里的 domestic）一律拒绝。
# 被 scripts/manage.sh source。

RELAY_BUNDLE_SRC="$ROOT/architecture/mx-launcher/server/scripts/site-slot-artifact-materializer.mjs"
declare -F note >/dev/null || note() { echo "  ${D}$*${O}"; }

relay_bundle_images() { # Launcher 的 Domestic 包里 docker compose 用的镜像，从生成器里读，换版本时跟着走
  grep -oE "image: [^' ]+" "$RELAY_BUNDLE_SRC" | awk '{print $2}' | sort -u
}

relay_full_ref() { # caddy:2.8.4-alpine → docker.io/library/caddy:2.8.4-alpine（ctr 要全名）
  local r="$1"
  [[ "$r" == */* ]] || r="library/$r"
  [[ "${r%%/*}" == *.* || "${r%%/*}" == *:* || "${r%%/*}" == localhost ]] || r="docker.io/$r"
  echo "$r"
}

relay_ssh() { qp-tunnel-cli edge ssh "$RELAY_HOST" -- "$@"; }

relay_guard() {
  local h="$1"
  [[ -n "$h" ]] || die "用法：relay <主机> check|docker|images|launcher-key [--context ladder2]（docs/57）"
  [[ "$h" != domestic ]] || die "domestic 是生产的 Domestic。relay 只给测试中继用（docs/48、docs/52）"
  [[ "$(host_field "$h" role)" == edge ]] || die "$h 不是 inventory 里 role: edge 的机器"
  local ip; ip="$(host_field "$h" public_ip)"
  site_is_ipv4 "$ip" || die "$h 没有登记 public_ip"
  site_ssh_allowlist "$INV_HOSTS" "$ip" >/dev/null || die "拒绝：$h 的地址 $ip 是生产 Domestic 的（docs/54）"
  command -v qp-tunnel-cli >/dev/null || die "本机没有 qp-tunnel-cli（边缘工具，docs/37）。relay 要在推送机（s2）上跑"
  [[ $EUID -eq 0 ]] || die "relay 要 root：边缘工具的密钥在 /var/lib/qp-tunnel/edge"
  RELAY_HOST="$h"; RELAY_IP="$ip"
}

relay_check() {
  local rc=0 img out
  if relay_ssh true >/dev/null 2>&1; then ok "边缘工具连得上 $RELAY_HOST（$RELAY_IP）"
  else bad "边缘工具连不上 $RELAY_HOST：qp-tunnel-cli edge ssh $RELAY_HOST"; return 1; fi
  if relay_ssh 'docker compose version' >/dev/null 2>&1; then ok "docker 和 compose 在"
  else bad "没有 docker 或 compose：./scripts/manage.sh relay $RELAY_HOST docker"; rc=1; fi
  while IFS= read -r img; do
    if relay_ssh "docker image inspect $img" >/dev/null 2>&1; then ok "镜像 $img 在"
    else bad "缺镜像 $img：./scripts/manage.sh relay $RELAY_HOST images"; rc=1; fi
  done < <(relay_bundle_images)
  local domain; domain="$(host_field "$RELAY_HOST" bootstrap_domain)"
  if [[ -n "$domain" ]]; then
    out="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}')"
    if [[ "$out" == "$RELAY_IP" ]]; then ok "$domain 解析到 $RELAY_IP"
    else bad "$domain 解析到 ${out:-（解析不到）}，不是 $RELAY_IP"; rc=1; fi
  fi
  out="$(relay_ssh "ss -Hlntu 2>/dev/null" 2>/dev/null)"
  if grep -qE 'tcp .*:443 ' <<<"$out"; then ok "443 有人在听（bootstrap 站点，docs/59）"
  else warn "443 没人在听：relay $RELAY_HOST site / cert 还没做（docs/59）"; fi
  if grep -qE 'udp .*:51280 ' <<<"$out"; then ok "UDP 51280 在听（中继 mx-domestic）"
  else warn "UDP 51280 没人在听：中继还没装（docs/57）"; fi
  return $rc
}

relay_docker() {
  if relay_ssh 'docker compose version' >/dev/null 2>&1; then ok "docker 和 compose 已经在 $RELAY_HOST 上"; return 0; fi
  relay_ssh 'command -v apt-get' >/dev/null 2>&1 || die "$RELAY_HOST 不是 apt 系的系统，docker 要手工装"
  echo "▶ 在 $RELAY_HOST 上装 docker.io 和 compose（apt，走它自己的软件源）"
  relay_ssh 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && (apt-get install -y -qq docker.io docker-compose-v2 || apt-get install -y -qq docker.io docker-compose-plugin) && systemctl enable --now docker' \
    || die "装 docker 失败（上面是输出）"
  relay_ssh 'docker compose version' >/dev/null 2>&1 || die "装完还是没有 docker compose"
  ok "docker 和 compose 装好了"
}

relay_images() {
  command -v ctr >/dev/null || die "本机没有 ctr（containerd）"
  local arch img ref ns=ladder2-relay
  arch="$(relay_ssh 'uname -m' 2>/dev/null | tr -d '\r')"
  case "$arch" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) die "读不到 $RELAY_HOST 的架构（$arch）" ;; esac
  [[ -n "${PROXY:-}" ]] || warn "没有设 PROXY：在 s2 上直连 Docker Hub 多半不通，一般写成 PROXY=http://127.0.0.1:7788"
  while IFS= read -r img; do
    if relay_ssh "docker image inspect $img" >/dev/null 2>&1; then ok "$RELAY_HOST 上已有 $img"; continue; fi
    ref="$(relay_full_ref "$img")"
    echo "▶ 在 s2 上拉 $ref（linux/$arch），推到 $RELAY_HOST"
    # 单独的命名空间，不混进 kubelet 用的 k8s.io
    env ${PROXY:+HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" http_proxy="$PROXY" https_proxy="$PROXY"} NO_PROXY=localhost,127.0.0.1 \
      ctr -n "$ns" images pull --platform "linux/$arch" "$ref" >/dev/null || die "拉不下来 $ref"
    ctr -n "$ns" images export --platform "linux/$arch" - "$ref" | relay_ssh 'docker load' >/dev/null || die "推到 $RELAY_HOST 失败：$ref"
    # docker load 进去的名字是全名，compose 写的是短名，补一个短名的标签
    relay_ssh "docker image inspect $img >/dev/null 2>&1 || docker tag $ref $img" >/dev/null 2>&1 || true
    relay_ssh "docker image inspect $img" >/dev/null 2>&1 && ok "$img" || die "$RELAY_HOST 上还是没有 $img"
  done < <(relay_bundle_images)
}

relay_launcher_key() { # 把 s2 上 Launcher 的 SSH 公钥（管理界面 SSH Profile 的 bootstrap 生成的）放进中继的 authorized_keys
  local ctx site key
  ctx="$(need_context "$@")"
  site="$RELAY_HOST"
  local a; for a in "$@"; do case "$a" in --site=*) site="${a#*=}" ;; esac; done
  key="$(kubectl --context "$ctx" -n mx-internal-shadow exec deploy/mx-launcher-internal -c internal-api -- \
    sh -c "cat \"\${MX_SITE_SLOT_SSH_KEY_DIR:-/app/artifacts/ssh}/${site}_rsa.pub\"" 2>/dev/null | tr -d '\r')"
  [[ "$key" == ssh-* ]] || die "Launcher 里还没有站点 $site 的 SSH 公钥：先在管理界面 Config Center 给 $site 做一次 SSH Profile bootstrap（不填密码，host 填 $RELAY_IP），再跑这一条（docs/57）"
  printf '%s\n' "$key" | relay_ssh 'umask 077; mkdir -p ~/.ssh; k="$(cat)"; touch ~/.ssh/authorized_keys; grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >>~/.ssh/authorized_keys' \
    || die "写不进 $RELAY_HOST 的 authorized_keys"
  ok "Launcher 的公钥（站点 $site）已在 $RELAY_HOST 的 authorized_keys 里。回管理界面点 SSH Profile 的检查"
}

# ---------- bootstrap 域名的 HTTPS（docs/59）----------
# 证书在 s2 上签、在 s2 上续，放进边缘工具的 state，随 edge push 推过去：和别的边缘配置一样从内往外推。
# Let's Encrypt 访问 domestic02:80 的挑战路径，domestic02 的 nginx 经边缘隧道转给 s2 上临时监听的 certbot。
RELAY_ACME_DIR=/var/lib/ladder2/acme
RELAY_ACME_PORT=18089

relay_state_dir() { echo "${QP_EDGE_HOME:-/var/lib/qp-tunnel/edge}/state/$RELAY_HOST/wg-nginx"; }

relay_domains() { # 这台中继上的公网域名，每行"域名 角色"：bootstrap（客户端）、admin（Launcher 管理后台，docs/61）
  local d
  d="$(host_field "$RELAY_HOST" bootstrap_domain)"; [[ -n "$d" ]] && echo "$d bootstrap"
  d="$(host_field "$RELAY_HOST" admin_domain)"; [[ -n "$d" ]] && echo "$d admin"
  return 0
}

relay_domain_mode() { # relay_domain_mode <角色> → client | open | restricted
  local state; state="$(relay_state_dir)"
  local saved; saved="$(cat "$state/ladder2-access-$1" 2>/dev/null || true)"
  if [[ -n "$saved" ]]; then echo "$saved"
  elif [[ "$1" == admin ]]; then echo open
  else echo client; fi
}

relay_site_render() { # 写 nginx/ladder2-bootstrap.conf：公共部分 + 每个域名一段；证书在 state 里的才带 443
  local state link allow_file allow_lines="" cidr
  state="$(relay_state_dir)"
  [[ -f "$state/wg/relay.conf" ]] || die "没有 $state/wg/relay.conf：这台的边缘隧道不是这台推送机建的（qp-tunnel-cli edge relations）"
  link="$(host_field s2 wg_ip)"; site_is_ipv4 "$link" || die "inventory 里 s2 的 wg_ip（边缘隧道地址）不是地址：$link"
  allow_file="$state/ladder2-admin-allow"
  if [[ -f "$allow_file" ]]; then
    while IFS= read -r cidr; do [[ -n "$cidr" ]] && allow_lines+="    $cidr 1;"$'\n'; done <"$allow_file"
  fi
  local domains; domains="$(relay_domains)"
  [[ -n "$domains" ]] || die "inventory 里 $RELAY_HOST 没有 bootstrap_domain / admin_domain"
  install -d -m 700 "$state/nginx"
  local out="$state/nginx/ladder2-bootstrap.conf" tmp domain role mode tls
  tmp="$(mktemp)"
  LADDER2_ADMIN_ALLOW="$allow_lines" awk '/^@ADMIN_ALLOW@$/ { printf "%s", ENVIRON["LADDER2_ADMIN_ALLOW"]; next } { print }' \
    "$ROOT/infra/edge/bootstrap-site.conf.tmpl" >"$tmp"
  RELAY_DOMAINS_TLS=""; RELAY_DOMAINS_ALL=""
  while read -r domain role; do
    [[ "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "inventory 里 $RELAY_HOST 的 $role 域名不是域名：$domain"
    mode="$(relay_domain_mode "$role")"
    tls=0; [[ -f "$state/certs/$domain.crt" && -f "$state/certs/$domain.key" ]] && tls=1
    sed -e "s#@DOMAIN@#$domain#g" -e "s#@ROLE@#$role#g" -e "s#@MODE@#$mode#g" \
        -e "s#@UPSTREAM@#$link:18090#g" -e "s#@ACME_UPSTREAM@#$link:$RELAY_ACME_PORT#g" \
        "$ROOT/infra/edge/bootstrap-site.server.tmpl" | awk -v tls="$tls" '
      /^@TLS_BEGIN@$/ { skip = (tls != 1); next }
      /^@TLS_END@$/ { skip = 0; next }
      !skip { print }' >>"$tmp"
    RELAY_DOMAINS_ALL+="$domain "
    if (( tls )); then RELAY_DOMAINS_TLS+="$domain "; ok "https://$domain（$role，$mode）"
    else warn "$domain（$role，$mode）：证书还没签，只有 80。下一步：relay $RELAY_HOST cert --agree-tos"; fi
    case "$mode" in
      open) [[ "$role" == bootstrap ]] && warn "$domain 全部放行：控制面对公网开着（docs/60）。客户端域名建议 --bootstrap-access client" ;;
      restricted)
        if [[ -s "$allow_file" ]]; then note "$domain：客户端接口 + 来源 $(tr '\n' ' ' <"$allow_file")"
        else warn "$domain 是 restricted 但没有登记来源：只剩客户端接口。relay $RELAY_HOST site --admin-allow <IP,...>"; fi ;;
    esac
  done <<<"$domains"
  install -m 600 "$tmp" "$out"; rm -f "$tmp"
  RELAY_LINK="$link"
  return 0
}

relay_push() {
  echo "▶ qp-tunnel-cli edge push $RELAY_HOST --stack wg-nginx"
  if ! qp-tunnel-cli edge push "$RELAY_HOST" --stack wg-nginx --yes; then
    die "edge push 失败（上面是原因）。如果提示有不是 edge 推的组件（Launcher 推过 Domestic 包），加 --shared-host 再推一次：qp-tunnel-cli edge push $RELAY_HOST --stack wg-nginx --shared-host --yes（docs/57）"
  fi
}

relay_set_mode() { # relay_set_mode <角色> <模式>
  local role="$1" mode="$2" state; state="$(relay_state_dir)"
  case "$role:$mode" in
    bootstrap:client|bootstrap:open|bootstrap:restricted|admin:open|admin:restricted) ;;
    *) die "$role 域名的模式只能是 $([[ "$role" == admin ]] && echo "open、restricted" || echo "client、open、restricted")：$mode" ;;
  esac
  install -d -m 700 "$state"; printf '%s\n' "$mode" >"$state/ladder2-access-$role"
}

relay_site() { # relay <主机> site [--bootstrap-access client|open|restricted] [--admin-access open|restricted] [--admin-allow <IP,...>|none] [--no-push]
  local push=1 allow="" set_allow=0
  while (( $# )); do
    case "$1" in
      --bootstrap-access|--access) relay_set_mode bootstrap "${2:-}"; shift 2 ;;
      --bootstrap-access=*|--access=*) relay_set_mode bootstrap "${1#*=}"; shift ;;
      --admin-access) relay_set_mode admin "${2:-}"; shift 2 ;;
      --admin-access=*) relay_set_mode admin "${1#*=}"; shift ;;
      --admin-allow) allow="${2:-}"; set_allow=1; shift 2 ;;
      --admin-allow=*) allow="${1#*=}"; set_allow=1; shift ;;
      --no-push) push=0; shift ;;
      --context|--context=*) [[ "$1" == --context ]] && shift; shift ;;
      *) die "不认识的参数：$1" ;;
    esac
  done
  local state; state="$(relay_state_dir)"
  # docs/60 的旧文件（一个模式管全部）不再用：每个域名各有模式（docs/61）
  [[ -f "$state/ladder2-access" ]] && { rm -f "$state/ladder2-access"; note "旧的 ladder2-access 不再用了：现在按域名分别设模式（docs/61）"; }
  if (( set_allow )); then
    install -d -m 700 "$state"
    if [[ "$allow" == none || -z "$allow" ]]; then rm -f "$state/ladder2-admin-allow"; ok "登记的来源清空了"
    else
      local cidr list=()
      for cidr in ${allow//,/ }; do
        [[ "$cidr" == */* ]] || cidr="$cidr/32"
        site_is_ipv4 "${cidr%/*}" && [[ "${cidr#*/}" =~ ^([0-9]|[12][0-9]|3[0-2])$ ]] || die "不是 IPv4 地址或网段：$cidr"
        [[ "${cidr#*/}" -ge 16 ]] || die "$cidr 太大了：只放具体的来源（/16 以内）"
        list+=("$cidr")
      done
      printf '%s\n' "${list[@]}" >"$state/ladder2-admin-allow"; chmod 600 "$state/ladder2-admin-allow"
    fi
  fi
  relay_site_render
  (( push )) && relay_push || true
}

relay_cert() { # relay <主机> cert --agree-tos [--email <地址>] [--domain <域名>]
  local agree=0 email="" only=""
  while (( $# )); do
    case "$1" in
      --agree-tos) agree=1; shift ;;
      --email) email="${2:-}"; shift 2 ;;
      --email=*) email="${1#*=}"; shift ;;
      --domain) only="${2:-}"; shift 2 ;;
      --domain=*) only="${1#*=}"; shift ;;
      --context|--context=*) [[ "$1" == --context ]] && shift; shift ;;
      *) die "不认识的参数：$1" ;;
    esac
  done
  (( agree )) || die "签 Let's Encrypt 的证书要同意它的用户协议（https://letsencrypt.org/repository/）。同意的话加 --agree-tos；--email 可选，用来收到期提醒"
  relay_site_render
  relay_push
  if ! command -v certbot >/dev/null; then
    echo "▶ s2 上装 certbot"
    DEBIAN_FRONTEND=noninteractive apt-get ${PROXY:+-o Acquire::http::Proxy="$PROXY" -o Acquire::https::Proxy="$PROXY"} install -y -qq certbot >/dev/null \
      || die "装 certbot 失败"
  fi
  install -d -m 700 "$RELAY_ACME_DIR"
  local who=(--register-unsafely-without-email); [[ -n "$email" ]] && who=(--email "$email")
  local domain seen changed=0 issued=0
  for domain in $RELAY_DOMAINS_ALL; do
    [[ -z "$only" || "$only" == "$domain" ]] || continue
    seen="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}')"
    if [[ "$seen" != "$RELAY_IP" ]]; then
      warn "跳过 $domain：解析到 ${seen:-（解析不到）}，不是 $RELAY_IP。DNS 加好以后再跑 relay $RELAY_HOST cert --agree-tos --domain $domain"
      continue
    fi
    if [[ -f "$RELAY_ACME_DIR/config/live/$domain/fullchain.pem" ]]; then
      note "$domain 已经有证书，到期前由定时器续"
    else
      echo "▶ 给 $domain 签证书：Let's Encrypt → $RELAY_HOST:80 → 边缘隧道 → s2 $RELAY_LINK:$RELAY_ACME_PORT"
      env ${PROXY:+HTTPS_PROXY="$PROXY" https_proxy="$PROXY"} NO_PROXY="localhost,127.0.0.1,$RELAY_LINK" \
        certbot certonly --standalone --non-interactive --agree-tos "${who[@]}" \
          --preferred-challenges http --http-01-address "$RELAY_LINK" --http-01-port "$RELAY_ACME_PORT" \
          --config-dir "$RELAY_ACME_DIR/config" --work-dir "$RELAY_ACME_DIR/work" --logs-dir "$RELAY_ACME_DIR/logs" \
          -d "$domain" || die "签 $domain 的证书失败（上面是 certbot 的输出）。确认它解析到 $RELAY_IP、阿里云安全组放行 TCP 80（docs/59）"
      issued=1
    fi
    relay_cert_install "$domain" && changed=1
  done
  (( changed )) && { relay_site_render && relay_push; }
  relay_cert_timer
  ok "证书每天检查一次，快到期时在 s2 上续、自动推过去（ladder2-acme-renew.timer）"
}

relay_cert_install() { # relay_cert_install <域名>：把 certbot 的证书拷进边缘工具的 state；变了才返回 0
  local domain="$1" live="$RELAY_ACME_DIR/config/live/$1" certs; certs="$(relay_state_dir)/certs"
  [[ -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]] || return 1
  install -d -m 700 "$certs"
  if cmp -s "$live/fullchain.pem" "$certs/$domain.crt" && cmp -s "$live/privkey.pem" "$certs/$domain.key"; then
    return 1
  fi
  install -m 644 "$live/fullchain.pem" "$certs/$domain.crt"
  install -m 600 "$live/privkey.pem" "$certs/$domain.key"
  ok "$domain 的证书放进了 $certs"
}

relay_cert_renew() { # 定时器调用：续期，有新证书就推过去
  relay_site_render >/dev/null
  env ${PROXY:+HTTPS_PROXY="$PROXY" https_proxy="$PROXY"} NO_PROXY="localhost,127.0.0.1,$RELAY_LINK" \
    certbot renew --non-interactive --config-dir "$RELAY_ACME_DIR/config" --work-dir "$RELAY_ACME_DIR/work" --logs-dir "$RELAY_ACME_DIR/logs" \
    || die "certbot renew 失败"
  local domain changed=0
  for domain in $RELAY_DOMAINS_ALL; do relay_cert_install "$domain" && changed=1; done
  (( changed )) && { relay_site_render && relay_push; }
  return 0
}

relay_cert_timer() {
  cat >/etc/systemd/system/ladder2-acme-renew.service <<UNIT
# de-ladder2（docs/59、docs/61）。续 $RELAY_HOST 上各域名的证书（$RELAY_DOMAINS_ALL），有新证书就推过去
[Unit]
Description=ladder2 renew the bootstrap certificate of $RELAY_HOST
[Service]
Type=oneshot
${PROXY:+Environment=PROXY=$PROXY}
ExecStart=$ROOT/scripts/manage.sh relay $RELAY_HOST cert-renew
UNIT
  cat >/etc/systemd/system/ladder2-acme-renew.timer <<'UNIT'
# de-ladder2（docs/59）
[Unit]
Description=ladder2 renew the bootstrap certificate daily
[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload && systemctl enable --now ladder2-acme-renew.timer >/dev/null 2>&1 && ok "定时续期 ladder2-acme-renew.timer 已启用"
}

cmd_relay() {
  local h="${1:-}" sub="${2:-}"; shift 2 || true
  relay_guard "$h"
  case "$sub" in
    check) relay_check ;;
    docker) relay_docker ;;
    images) relay_images ;;
    launcher-key) relay_launcher_key "$@" ;;
    site) relay_site "$@" ;;
    cert) relay_cert "$@" ;;
    cert-renew) relay_cert_renew ;;
    *) die "用法：relay $h check|docker|images|launcher-key|site|cert（docs/57、docs/59）" ;;
  esac
}
