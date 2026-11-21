#!/usr/bin/env bash
# 角色脚本的公共函数。被 scripts/roles/*/NN-*.sh 引用，不单独运行。
# 由 ./scripts/manage.sh node prepare <主机> <阶段> 调用，在目标机器本机以 root 运行（docs/35）。
set -euo pipefail

ROLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$ROLES_DIR/../.." && pwd)"
INV_HOSTS="$ROOT/inventory/hosts.yaml"
# shellcheck source=../../infra/k8s/versions.env
source "$ROOT/infra/k8s/versions.env"

HOST="${LADDER2_HOST:-}"
[[ -n "$HOST" ]] || { echo "错误：LADDER2_HOST 没有设置。用 ./scripts/manage.sh node prepare <主机> <阶段> 运行。" >&2; exit 1; }

say()  { echo "▶ $*"; }
done_() { echo "  ✓ $*"; }
note() { echo "  · $*"; }
die()  { echo "错误：$*" >&2; exit 1; }

need_root() { [[ $EUID -eq 0 ]] || die "要用 root 运行：sudo ./scripts/manage.sh node prepare $HOST <阶段>"; }

host_field() { # host_field <主机> <字段>：inventory/hosts.yaml 里单行的字段
  awk -v h="$1" -v f="$2" '
    /^hosts:/{inh=1;next} /^[a-z_]+:/{inh=0}
    inh && /^  [a-z0-9_-]+:[ ]*$/{cur=$1; sub(":","",cur); next}
    inh && cur==h && $1==f":"{ $1=""; sub(/^ +/,""); sub(/ +#.*$/,""); print; exit }' "$INV_HOSTS"
}

host_block() { # host_block <主机> <字段>：">-" 折叠写法的多行字段，拼成一行
  awk -v h="$1" -v f="$2" '
    /^hosts:/{inh=1;next} /^[a-z_]+:/{inh=0}
    inh && /^  [a-z0-9_-]+:[ ]*$/{cur=$1; sub(":","",cur); grab=0; next}
    inh && cur==h && $1==f":"{ grab=1; next }
    grab && /^      /{ sub(/^ +/,""); out=(out=="" ? $0 : out " " $0); next }
    grab{ grab=0 }
    END{ print out }' "$INV_HOSTS"
}

is_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }

local_ips() {
  if command -v ip >/dev/null; then ip -4 -o addr show | awk '{split($4,a,"/"); print a[1]}'
  else ifconfig 2>/dev/null | awk '$1=="inet"{print $2}'; fi
}

# 防护：任何角色脚本都不在 s1 上运行（CLAUDE.md 的硬约束），也不在不是目标的机器上运行。
guard_target() {
  local role lan s1ip
  role="$(host_field "$HOST" role)"
  [[ -n "$role" ]] || die "inventory/hosts.yaml 里没有主机 $HOST"
  [[ "$role" != l1 ]] || die "$HOST 是现役的 L1。本工程不对它做任何准备（docs/16）。"
  s1ip="$(host_field s1 lan_ip)"
  if [[ -n "$s1ip" ]] && local_ips | grep -qx "$s1ip"; then
    die "本机有 s1 的地址 $s1ip。角色脚本不在 s1 上运行。"
  fi
  lan="$(host_field "$HOST" lan_ip)"
  is_ip "$lan" || die "$HOST 的 lan_ip 没有登记成地址：$lan"
  local_ips | grep -qx "$lan" || die "本机没有地址 $lan，不是 $HOST。登录 $HOST 再运行。"
  LAN_IP="$lan"
}

CHANGED=0
# write_file <路径> [权限] < 内容：内容相同就不动；不同就先把旧的留一份 <路径>.ladder2-<时间>，再写。
write_file() {
  local path="$1" mode="${2:-0644}" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  if [[ -f "$path" ]] && cmp -s "$tmp" "$path"; then rm -f "$tmp"; note "$path 没有变化"; return 0; fi
  if [[ -f "$path" ]]; then cp -a "$path" "$path.ladder2-$(date +%Y%m%d%H%M%S)"; fi
  install -D -m "$mode" "$tmp" "$path"; rm -f "$tmp"
  echo "  ✎ $path"; CHANGED=1
}

backup_once() { # 改系统文件之前留一份
  [[ -f "$1" ]] && cp -a "$1" "$1.ladder2-$(date +%Y%m%d%H%M%S)"
  return 0
}

# 出网代理（CLAUDE.md）：PROXY=http://127.0.0.1:7788。只给下载用，不改全局。
NO_PROXY_LIST="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,.svc,.cluster.local,k8s-api.ladder2.internal"
dl() { curl -fsSL --retry 3 --connect-timeout 10 ${PROXY:+--proxy "$PROXY"} "$@"; }
apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -y -q \
    ${PROXY:+-o Acquire::http::Proxy="$PROXY" -o Acquire::https::Proxy="$PROXY"} "$@"
}
need_apt() { command -v apt-get >/dev/null || die "只写了 apt 的做法（s2 是 Ubuntu）。别的系统参考 L1 的 install-k8s-centos.sh。"; }
