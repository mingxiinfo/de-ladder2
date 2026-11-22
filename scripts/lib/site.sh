#!/usr/bin/env bash
# 机器地址这类"每台推送机、每个时间点可能不一样"的值（docs/50）。
# 被 scripts/manage.sh、scripts/roles/lib.sh、infra/k8s/platform/install.sh 引用，不单独运行。
#
# 优先级：命令前的环境变量 > 本工程根目录的 .env（不进 Git）> inventory/hosts.yaml。
#   LADDER2_S2_LAN_IP=192.168.0.120 ./scripts/manage.sh node verify s2
#   sudo LADDER2_S2_LAN_IP=192.168.0.120 ./scripts/manage.sh node prepare s2 host   # 和 PROXY 一样写在 sudo 后面
# 变量名是 LADDER2_<主机>_LAN_IP（主机名大写，- 换成 _）。s1 不能这样改：
# 所有写操作都靠 s1 的地址认出 s1 并拒绝执行（CLAUDE.md 的硬约束），这个地址只认 inventory。

SITE_ROOT="${SITE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# .env 只收 LADDER2_* 和 PROXY，逐行解析，不当 shell 执行；已经在环境里的不覆盖。
site_load_env() {
  local file="$SITE_ROOT/.env" line key value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(LADDER2_[A-Z0-9_]+|PROXY)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    value="${value%%[[:space:]]#*}"; value="${value%"${value##*[![:space:]]}"}"
    [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]] && value="${BASH_REMATCH[1]}"
    [[ -n "${!key+x}" ]] && continue
    export "$key=$value"
  done <"$file"
}

site_is_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1}"; do (( 10#$o <= 255 )) || return 1; done
}

# site_check_env：LADDER2_*_LAN_IP 写错了就在一开始停下，不要带着错地址往下做
site_check_env() {
  local var
  for var in $(compgen -v | grep -E '^LADDER2_[A-Z0-9_]+_LAN_IP$' || true); do
    site_is_ipv4 "${!var}" || { echo "错误：$var=${!var} 不是 IPv4 地址（docs/50）" >&2; return 1; }
    [[ "$var" == LADDER2_S1_LAN_IP ]] && echo "提示：LADDER2_S1_LAN_IP 不起作用，s1 的地址只认 inventory/hosts.yaml（防止误认 s1）" >&2
  done
  return 0
}

site_env_name() { # site_env_name <主机> <字段> → LADDER2_S2_LAN_IP
  printf 'LADDER2_%s_%s' "$1" "$2" | tr '[:lower:]-' '[:upper:]_'
}

# site_host_field <inventory 文件> <主机> <字段>：inventory 的值，lan_ip 可以被环境变量覆盖
site_host_field() {
  local inv="$1" h="$2" f="$3" var
  if [[ "$f" == lan_ip && "$h" != s1 ]]; then
    var="$(site_env_name "$h" "$f")"
    if [[ -n "${!var:-}" ]]; then
      site_is_ipv4 "${!var}" || { echo "错误：$var=${!var} 不是 IPv4 地址" >&2; return 1; }
      echo "${!var}"; return 0
    fi
  fi
  awk -v h="$h" -v f="$f" '
    /^hosts:/{inh=1;next} /^[a-z_]+:/{inh=0}
    inh && /^  [a-z0-9_-]+:[ ]*$/{cur=$1; sub(":","",cur); next}
    inh && cur==h && $1==f":"{ $1=""; sub(/^ +/,""); sub(/ +#.*$/,""); print; exit }' "$inv"
}

# site_lan_source <主机>：这个地址从哪来的，给人看
site_lan_source() {
  local var; var="$(site_env_name "$1" lan_ip)"
  if [[ "$1" != s1 && -n "${!var:-}" ]]; then echo "$var"; else echo "inventory/hosts.yaml"; fi
}

# site_expand <inventory 文件> <文本>：把 @S2_LAN_IP@ 这类占位换成对应主机的地址
site_expand() {
  local inv="$1" text="$2" token host ip
  while [[ "$text" =~ @([A-Z0-9_]+)_LAN_IP@ ]]; do
    token="${BASH_REMATCH[0]}"
    host="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]_' '[:lower:]-')"
    ip="$(site_host_field "$inv" "$host" lan_ip)" || return 1
    [[ -n "$ip" ]] || { echo "错误：$token 对应的主机 $host 没有登记 lan_ip" >&2; return 1; }
    text="${text//"$token"/$ip}"
  done
  printf '%s' "$text"
}
