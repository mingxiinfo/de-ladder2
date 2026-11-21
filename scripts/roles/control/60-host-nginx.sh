#!/usr/bin/env bash
# 阶段 host-nginx：s2 的宿主机 Nginx，80 端口的唯一主人（docs/05、docs/23、docs/35）。
# 只装在 s2 上。s1 的 host-nginx 不动。
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_root
guard_target
need_apt

say "Nginx"
if ! command -v nginx >/dev/null; then apt_get install nginx >/dev/null; fi
done_ "$(nginx -v 2>&1)"

say "80 端口没有别人占"
other="$(ss -ltnpH 'sport = :80' 2>/dev/null | grep -v '"nginx"' || true)"
[[ -z "$other" ]] || die "80 端口已经有别的程序在监听，不装：
$other"

say "连接数（1000 QPS，docs/35）"
conf=/etc/nginx/nginx.conf
if ! grep -qE '^\s*worker_connections\s+16384;' "$conf" || ! grep -qE '^\s*worker_rlimit_nofile\s+' "$conf"; then
  backup_once "$conf"
  sed -i -E 's/^(\s*)worker_connections\s+[0-9]+;/\1worker_connections 16384;/' "$conf"
  grep -qE '^\s*worker_rlimit_nofile\s+' "$conf" || sed -i -E 's/^(worker_processes\s+[^;]+;)/\1\nworker_rlimit_nofile 65535;/' "$conf"
  grep -qE '^\s*worker_connections\s+16384;' "$conf" || die "$conf 里没找到 worker_connections，格式和预期不同，人工改"
  echo "  ✎ $conf：worker_connections 16384，worker_rlimit_nofile 65535"
  CHANGED=1
else
  note "已是目标值"
fi

say "站点配置"
tmp="$(mktemp)"
sed -e "s#@LAN_IP@#$LAN_IP#g" -e "s#@PUBLIC_PORT@#$GATEWAY_PUBLIC_NODEPORT#g" -e "s#@INTERNAL_PORT@#$GATEWAY_INTERNAL_NODEPORT#g" \
  "$ROOT/infra/nginx/s2/ladder2.conf.tmpl" >"$tmp"
write_file /etc/nginx/conf.d/ladder2.conf <"$tmp"   # 不用管道：管道里改的 CHANGED 带不回来
rm -f "$tmp"
# Ubuntu 自带的默认站点也是 default_server，两个会冲突。只去掉 sites-enabled 里的链接，sites-available 里的原文件不动。
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  rm /etc/nginx/sites-enabled/default
  echo "  ✎ 停用 Ubuntu 的默认站点（/etc/nginx/sites-available/default 还在）"
  CHANGED=1
fi

say "检查配置并生效"
nginx -t
systemctl enable nginx >/dev/null 2>&1
if systemctl is-active -q nginx; then
  if (( CHANGED )); then systemctl reload nginx; echo "  ↻ 已 reload"; fi
else
  systemctl start nginx
fi
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$LAN_IP/gateway-health" || true)"
[[ "$code" == 200 ]] || die "http://$LAN_IP/gateway-health 返回 $code"
done_ "http://$LAN_IP/gateway-health 200"
