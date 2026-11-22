#!/usr/bin/env bash
# relay <主机> check|docker|images|launcher-key（docs/57）
# 让 Launcher 管理界面能把 Domestic 包（中继 mx-domestic、边缘、DNS、443 的 HTTPS）推到测试中继上：
# 那个包要目标机有 docker、有两个镜像、认 Launcher 的 SSH 公钥。这几样由推送机（s2）经 L2 的边缘工具
# （qp-tunnel-cli edge ssh，用 /var/lib/qp-tunnel/edge 的密钥）准备好。镜像在 s2 上经代理拉，再推过去：
# 数据从内往外推（CLAUDE.md），domestic02 自己不用连 Docker Hub。
# 只给测试中继用：生产的 Domestic（inventory 里的 domestic）一律拒绝。
# 被 scripts/manage.sh source。

RELAY_BUNDLE_SRC="$ROOT/architecture/mx-launcher/server/scripts/site-slot-artifact-materializer.mjs"

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
  if grep -qE 'tcp .*:443 ' <<<"$out"; then ok "443 有人在听（Launcher 推的 public-tls）"
  else warn "443 没人在听：Launcher 的 Domestic 包还没推，或者 public-tls 还没起（docs/57）"; fi
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

cmd_relay() {
  local h="${1:-}" sub="${2:-}"; shift 2 || true
  relay_guard "$h"
  case "$sub" in
    check) relay_check ;;
    docker) relay_docker ;;
    images) relay_images ;;
    launcher-key) relay_launcher_key "$@" ;;
    *) die "用法：relay $h check|docker|images|launcher-key [--context ladder2] [--site=<站点>]（docs/57）" ;;
  esac
}
