#!/usr/bin/env bash
# de-ladder2 的统一入口。命令和规矩见 docs/12.ops-and-manage.md。
# 薄入口：子项目继续用自己的 manage.sh，这里只负责找到它并转调。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INV_PROJECTS="inventory/projects.yaml"
INV_HOSTS="inventory/hosts.yaml"
K8S="infra/k8s"
# shellcheck source=../infra/k8s/versions.env
source "$K8S/versions.env"

if [[ -t 1 ]]; then B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; O=$'\033[0m'
else B=""; D=""; G=""; Y=""; R=""; O=""; fi

die()  { echo "${R}错误：${O}$*" >&2; exit 1; }
ok()   { echo "  ${G}✓${O} $*"; }
warn() { echo "  ${Y}!${O} $*"; }
bad()  { echo "  ${R}✗${O} $*"; FAILED=1; }
FAILED=0

usage() {
  cat <<EOF
${B}de-ladder2${O}  集群架构与知识库（文档从 docs/README.md 开始）

${B}只读${O}
  list                      登记的项目：类别、迁移状态、路径是否存在
  hosts                     登记的主机
  docs                      文档列表和状态行
  check                     离线检查：脚本语法、清单渲染、文档编号和链接
  doctor                    本机工具；在服务器上还检查磁盘、NAS 挂载、端口
  k8s render <目录>         打印渲染后的清单，例如 k8s render platform/gateway
  k8s status --context <名字>   节点、网关、数据库集群的状态
  k8s capacity --context <名字> 每台节点可分配、被 requests 占了多少、实际用量、标签和污点、本地卷在哪台（docs/47）
  node verify <主机> [阶段] [--context <名字>]   逐个阶段检查做完没有，服务起来没有（docs/35）
  l1 <list|plan|status|doctor> [参数]   转调 L1 的统一入口（只放行只读命令）
  app list | app render <名字> [环境]   architecture/、services/、projects/ 下的清单（docs/46）
  app status <项目> [环境] --context <名字>   项目在集群里的状态：工作负载、卷、路由、数据库、Secret 有没有
  image list <项目>         overlay 要的镜像，本机 docker 和 containerd 里有没有
  secret plan <项目> --from <目录> [--context <名字>]   对照 deploy/secrets.list 看缺什么（不显示值）
  node plan <主机>          这台机器按它的角色要做哪些步骤；s2 是 14 个阶段的表
  backup plan               备份什么、用什么、放哪（inventory/backup.yaml）
  disk record | disk trend  记录本机磁盘用量 / 按记录算增长和余量
  probe url <地址> [--host <域名>]      测一个地址各阶段的耗时（只发 GET）
  probe list | probe route <名字>       inventory/probes.yaml 登记的链路，逐层测并对比
  probe wg                  本机 WireGuard 各对端的最近握手时间
  loadtest results          每条链路每一层最近一次压测的结果

${B}写入${O}（必须指名目标）
  node prepare <主机> <阶段> [--context <名字>]      做一个阶段（一次一个）。机器上的阶段要在那台机器上 sudo 运行（docs/35）
  k8s platform <组件> --context <名字>               往指定集群装平台组件：flannel、local-path、metrics-server、gateway、postgres
  loadtest run <链路> --hop <层> [--rate 1000] --context <名字>   压一层：service、gateway、host-nginx、edge（docs/35）
  loadtest pg [--rate 1000] [--mode select|write] --context <名字>  压 pg-common
  app deploy <项目> [环境] [--full] --context <名字> 一次完整的部署：检查 → 没跑过的一次性步骤 → apply → 等滚动 → 验证，每段计时（docs/47）
  app diff|apply <项目> [环境] --context <名字>      对比 / 只 apply（先 platform/，再 bootstrap/ 里没有的，再 overlay）
  app once list|run|mark|archive <项目> [步骤] --context <名字>   一次性步骤：看台账、重跑、只记账、归档到 once/archive/
  image build <项目> [--platform linux/amd64]        从项目的 Dockerfile 构建，镜像名和版本号取 overlay 的 images:
  image save <项目> --out <文件>                     导出镜像，拷到没有 docker 的节点上用
  image import <项目> [--tar <文件>] --context <名字>  导入本节点的 containerd（sudo，每个节点各一次；还没有镜像仓库，docs/15 第 45 项）
  secret apply <项目> --from <目录> --context <名字>  从推送机本地目录建 Secret，值不打印、不进 Git
  run <项目> <命令...>                               转调该项目自己的 scripts/manage.sh
  diagrams [名字]                                    用 archify 生成 docs/atlas 和 design/architecture 的图
  design stage|serve|build|up|stop|status|export     查看设计文档的站点（工具，不属于架构）：组装、预览、打镜像、启动（docs/31、32）
                            内网服务器出网：PROXY=http://127.0.0.1:7788 ./scripts/manage.sh design build

${D}还没实现：node join、node prepare 通过 SSH 远程执行、backup run|verify、restore（docs/17、docs/19）；控制台（docs/26）${O}
EOF
}

# ---------- inventory ----------
# 清单是手写的简单 YAML：顶层键下面两格缩进是条目名，四格缩进是字段。不依赖 PyYAML。

root_path() { # root_path <键>  → roots: 下的绝对路径
  awk -v k="$1" '/^roots:/{r=1;next} /^[a-z]/{r=0} r && $1==k":"{print $2; exit}' "$INV_PROJECTS"
}

project_field() { # project_field <项目> <字段>
  awk -v p="$1" -v f="$2" '
    /^projects:/{inp=1;next}
    inp && /^  [A-Za-z0-9_-]+:[ ]*$/{cur=$1; sub(":","",cur); next}
    inp && cur==p && $1==f":"{ $1=""; sub(/^ +/,""); print; exit }' "$INV_PROJECTS"
}

project_names() {
  awk '/^projects:/{inp=1;next} inp && /^  [A-Za-z0-9_-]+:[ ]*$/{n=$1; sub(":","",n); print n}' "$INV_PROJECTS"
}

project_dir() { # 把 "dock/mx-pay" 这样的登记路径展开成绝对路径
  local raw prefix rest base
  raw="$(project_field "$1" path)"; [[ -n "$raw" ]] || return 1
  prefix="${raw%%/*}"; rest="${raw#*/}"
  base="$(root_path "$prefix")"
  if [[ -n "$base" ]]; then echo "$base/$rest"; else echo "$raw"; fi
}

cmd_list() {
  printf "${B}%-20s %-9s %-10s %-4s %s${O}\n" 项目 类别 L2状态 路径 位置
  local n dir mark
  while read -r n; do
    dir="$(project_dir "$n" || true)"
    if [[ -n "$dir" && -d "$dir" ]]; then mark="${G}有${O}"; else mark="${Y}无${O}"; fi
    printf "%-20s %-9s %-10s %b   %s\n" "$n" "$(project_field "$n" class)" "$(project_field "$n" l2_state | awk '{print $1}')" "$mark" "${dir:-—}"
  done < <(project_names)
  echo "${D}“无”表示这台机器上没有该路径（在服务器上运行时属正常）。登记文件：$INV_PROJECTS${O}"
}

cmd_hosts() {
  awk '
    /^hosts:/{h=1;next} /^[a-z_]+:/{h=0}
    function out(){ if(n) printf "%-12s %-8s %-9s %-16s %s\n", n, role, site, (lan!="" ? lan : (pub!="" ? pub : "—")), desc }
    h && /^  [a-z0-9_-]+:[ ]*$/{ out(); n=$1; sub(":","",n); site=role=desc=lan=pub=""; next }
    h && $1=="site:"{ site=$2 }
    h && $1=="role:"{ role=$2 }
    h && $1=="lan_ip:"{ lan=$2 }
    h && $1=="public_ip:"{ pub=$2 }
    h && $1=="desc:"{ $1=""; sub(/^ +/,""); desc=$0 }
    END{ out() }' "$INV_HOSTS"
  echo "${D}地址：内网机器写 LAN 地址，公网机器写公网地址，都没有登记的是 —。${O}"
  echo "${D}详细字段和来源：$INV_HOSTS${O}"
}

cmd_docs() {
  local f
  for f in docs/[0-9][0-9].*.md; do
    printf "${B}%s${O}\n  %s\n" "$f" "$(grep -m1 '^日期：' "$f" || echo '（缺少状态行）')"
  done
}

# ---------- check ----------

cmd_check() {
  echo "${B}脚本语法${O}"
  local f
  while read -r f; do
    if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
  done < <({ find scripts infra templates -name '*.sh' -type f; find architecture -path '*/scripts/manage.sh' -type f 2>/dev/null; } | sort)

  echo "${B}清单渲染${O}"
  if command -v kubectl >/dev/null; then
    while read -r f; do
      # base 目录只被 overlay 引用，单独渲染也应通过
      if kubectl kustomize "$(dirname "$f")" >/dev/null 2>&1; then ok "$(dirname "$f")"; else bad "$(dirname "$f")"; fi
    done < <(find infra templates services projects architecture -name kustomization.yaml -not -path '*/node_modules/*' 2>/dev/null | sort)
  else
    warn "未找到 kubectl，跳过"
  fi

  echo "${B}文档${O}"
  local prev=0 n
  for f in docs/[0-9][0-9].*.md; do
    n=$((10#$(basename "$f" | cut -c1-2)))
    (( n == prev + 1 )) || bad "编号不连续：$f（前一篇是 $prev）"
    grep -q '^日期：' "$f" || bad "缺少“日期：…状态：…”行：$f"
    grep -q "$(basename "$f")" docs/README.md || bad "docs/README.md 没有登记：$f"
    prev=$n
  done
  ok "编号 01–$(printf '%02d' "$prev")，状态行和索引"
  # 相对链接指向的文件要存在
  while IFS=: read -r f link; do
    [[ -e "$(dirname "$f")/$link" ]] || bad "$f 链接到不存在的文件：$link"
  done < <(grep -oE '\]\([^)#:]+\.md\)' -r docs README.md CLAUDE.md 2>/dev/null | sed -E 's/\]\(([^)]+)\)/\1/')
  ok "Markdown 相对链接"

  echo "${B}压测脚本${O}"
  if command -v node >/dev/null; then
    local tmpjs; tmpjs="$(mktemp -d)/http.mjs"; cp scripts/loadtest/http.js "$tmpjs"
    if node --check "$tmpjs" 2>/dev/null; then ok "scripts/loadtest/http.js 语法"; else bad "scripts/loadtest/http.js 语法错误"; fi
    rm -rf "$(dirname "$tmpjs")"
  else warn "未找到 node，跳过 k6 脚本的语法检查"; fi

  echo "${B}查看站点${O}"
  if python3 -m json.tool design/site/timeline.json >/dev/null 2>&1; then ok "design/site/timeline.json 是合法的 JSON"
  else bad "design/site/timeline.json 不是合法的 JSON"; fi

  echo "${B}清单里的版本${O}"
  # shellcheck source=/dev/null
  source "$K8S/versions.env"
  if grep -q "port: $GATEWAY_PUBLIC_NODEPORT" "$K8S/platform/gateway/ngf-values.yaml" \
     && grep -q "port: $GATEWAY_INTERNAL_NODEPORT" "$K8S/platform/gateway/ngf-values.yaml"; then
    ok "两个网关的 NodePort 与 versions.env 一致（$GATEWAY_PUBLIC_NODEPORT、$GATEWAY_INTERNAL_NODEPORT）"
  else bad "ngf-values.yaml 的 NodePort 与 versions.env 不一致"; fi
  if grep -q "podSubnet: $POD_CIDR" "$K8S/cluster/kubeadm-init.yaml" && grep -q "serviceSubnet: $SERVICE_CIDR" "$K8S/cluster/kubeadm-init.yaml"; then
    ok "kubeadm-init.yaml 的网段与 versions.env 一致"
  else bad "kubeadm-init.yaml 的网段与 versions.env 不一致"; fi
  local ph
  ph="$(grep -v '^#' "$K8S/cluster/kubeadm-init.yaml" | grep -o '@[A-Z0-9_]*@' | sort -u | tr '\n' ' ')"
  if [[ "$ph" == "@IMAGE_REPOSITORY@ @K8S_VERSION@ @LAN_IP@ @NODE_NAME@ @WG_IP@ " ]]; then ok "kubeadm-init.yaml 的占位都是 40-cluster.sh 会替换的"
  else bad "kubeadm-init.yaml 的占位和 40-cluster.sh 对不上：$ph"; fi
  local s2ip cni0; s2ip="$(host_field s2 lan_ip)"
  cni0="${POD_CIDR%/*}"; cni0="${cni0%.*}.1"   # 第一个节点分到 Pod 网段的第一个 /24，cni0 是其中的 .1
  if grep -q "value: $s2ip/32" "$K8S/platform/gateway/ngf-values.yaml" && grep -q "value: $cni0/32" "$K8S/platform/gateway/ngf-values.yaml"; then
    ok "网关信任的来源地址包含 s2 的 $s2ip 和 cni0 的 $cni0（docs/35）"
  else bad "ngf-values.yaml 的 trustedAddresses 和 s2 的地址、Pod 网段对不上"; fi
  check_launcher_consistency "$s2ip"

  echo
  if (( FAILED )); then die "检查没有通过。"; fi
  echo "${G}通过。${O}${D}这只证明能渲染，不证明在集群上能跑（infra/k8s/README.md 的“还没做的”）。${O}"
}

# ---------- doctor ----------

cmd_doctor() {
  echo "${B}工具${O}"
  local t
  for t in bash git kubectl helm node docker; do
    if command -v "$t" >/dev/null; then ok "$t"; else warn "$t 未安装"; fi
  done
  local ab="${ARCHIFY_BIN:-$HOME/.local/share/archify/archify/bin/archify.mjs}"
  if [[ -f "$ab" ]]; then ok "archify（$ab）"; else warn "archify 未安装（docs/13）"; fi

  if [[ "$(uname -s)" != Linux ]]; then
    echo "${D}不是 Linux，跳过磁盘、NAS、端口检查。这些在服务器上运行才有意义。${O}"; return 0
  fi

  echo "${B}磁盘（告警线 70%）${O}"
  local p use
  for p in / /data /mnt/nas; do
    if mountpoint -q "$p" 2>/dev/null || [[ "$p" == / ]]; then
      use="$(df -P "$p" | awk 'NR==2{gsub("%","",$5); print $5}')"
      if (( use >= 70 )); then bad "$p 已用 ${use}%"; else ok "$p 已用 ${use}%"; fi
    else
      warn "$p 不是挂载点"
    fi
  done

  echo "${B}NAS${O}"
  if mountpoint -q /mnt/nas 2>/dev/null; then
    if timeout 5 ls /mnt/nas >/dev/null 2>&1; then ok "/mnt/nas 可读"; else bad "/mnt/nas 已挂载但 5 秒内读不出（hard 挂载下 NAS 不可达会挂住）"; fi
  else
    warn "/mnt/nas 未挂载"
  fi

  echo "${B}端口归属（docs/05 的表）${O}"
  if command -v ss >/dev/null; then
    local port
    for port in 80 443 6443 8008 18090 30080 30081; do
      p="$(ss -ltnpH "sport = :$port" 2>/dev/null | awk '{print $NF}' | head -1)"
      echo "  $port  ${p:-（没有监听）}"
    done
    echo "${D}  对照 docs/05、docs/18：80 应该是 nginx；443 不应有监听；30080 / 30081 只在新集群的节点上有。${O}"
  else
    warn "没有 ss 命令"
  fi
  (( FAILED )) && exit 1 || true
}

# ---------- k8s ----------

need_context() { # 从参数里取 --context。写操作必须指名集群，不用当前默认的。
  local ctx=""
  while (( $# )); do
    case "$1" in --context) ctx="${2:-}"; shift 2 || true ;; --context=*) ctx="${1#*=}"; shift ;; *) shift ;; esac
  done
  [[ -n "$ctx" ]] || die "必须带 --context <名字>。s1 和 s2 是两个集群，这里不使用默认 context。"
  kubectl config get-contexts -o name 2>/dev/null | grep -qx "$ctx" || die "kubeconfig 里没有 context：$ctx"
  # 写操作不碰 s1 的集群（L1）：context 指向的 API 地址是 s1 的就拒绝
  local cl server ip
  cl="$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.cluster}")"
  server="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$cl\")].cluster.server}")"
  server="${server#*://}"; server="${server%%:*}"
  for ip in "$(host_field s1 lan_ip)" "$(host_field s1 wg_ip)" "$(host_field s1 openvpn_ip)"; do
    [[ -z "$ip" || "$server" != "$ip" ]] || die "context $ctx 指向 s1（$server）。本工程的写命令不碰 L1 的集群（CLAUDE.md）。"
  done
  echo "$ctx"
}

confirm() { # confirm <提示>；非交互时拒绝
  [[ -t 0 ]] || die "需要人工确认，不能在非交互环境执行。"
  local a; read -r -p "$1 输入 yes 继续：" a; [[ "$a" == yes ]] || die "已取消。"
}

cmd_k8s() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    render)
      [[ -n "${1:-}" && -f "$K8S/$1/kustomization.yaml" ]] || die "用法：k8s render <目录>，例如 platform/gateway"
      kubectl kustomize "$K8S/$1" ;;
    platform)
      [[ "${1:-}" =~ ^(flannel|local-path|metrics-server|gateway|postgres)$ ]] \
        || die "用法：k8s platform <flannel|local-path|metrics-server|gateway|postgres> --context <名字>"
      local comp="$1" ctx; ctx="$(need_context "$@")"
      echo "将往集群 ${B}$ctx${O} 安装 ${B}$comp${O}（版本见 $K8S/versions.env）。"
      confirm "这会修改集群。"
      PROXY="${PROXY:-}" bash "$K8S/platform/install.sh" "$comp" "$ctx" ;;
    capacity)
      k8s_capacity "$(need_context "$@")" ;;
    status)
      local ctx; ctx="$(need_context "$@")"
      local k=(kubectl --context "$ctx" --request-timeout=10s)
      echo "${B}节点${O}";       "${k[@]}" get nodes -o wide || { echo "UNKNOWN：连不上集群 $ctx"; exit 2; }
      echo "${B}网关${O}";       "${k[@]}" get gateway,httproute -A 2>/dev/null || echo "  UNKNOWN 或未安装"
      echo "${B}数据库集群${O}"; "${k[@]}" get clusters.postgresql.cnpg.io -A 2>/dev/null || echo "  UNKNOWN 或未安装" ;;
    *) die "用法：k8s render <目录> | status|capacity --context <名字> | platform <组件> --context <名字>" ;;
  esac
}

# ---------- 转调 ----------

cmd_l1() {
  local sub="${1:-}"
  case "$sub" in list|plan|status|doctor) ;; *) die "l1 只放行 list、plan、status、doctor。要在 s1 上部署，登录 s1 用 L1 自己的入口。" ;; esac
  local entry; entry="$(root_path dock)/scripts/manage.sh"
  [[ -f "$entry" ]] || die "找不到 L1 入口：$entry"
  ( cd "$(dirname "$entry")/.." && bash scripts/manage.sh "$@" )
}

cmd_run() {
  local proj="${1:-}"; shift || true
  [[ -n "$proj" && $# -gt 0 ]] || die "用法：run <项目> <命令...>。项目名见 list。"
  [[ "$proj" != mx-launcher || "$1" =~ ^(status|plan|list|doctor)$ ]] \
    || die "mx-launcher 承载 MX-H2I 的登录和联网。这里只转调它的只读命令；其他操作登录 s1 用它自己的入口。"
  local dir; dir="$(project_dir "$proj")" || die "没有登记的项目：$proj"
  [[ -f "$dir/scripts/manage.sh" ]] || die "$proj 没有 scripts/manage.sh（$dir）"
  ( cd "$dir" && bash scripts/manage.sh "$@" )
}

# app、image、secret 在 scripts/lib/apps.sh（docs/46）。

# ---------- node / backup / disk ----------

host_field() { # host_field <主机> <字段>
  awk -v h="$1" -v f="$2" '
    /^hosts:/{inh=1;next} /^[a-z_]+:/{inh=0}
    inh && /^  [a-z0-9_-]+:[ ]*$/{cur=$1; sub(":","",cur); next}
    inh && cur==h && $1==f":"{ $1=""; sub(/^ +/,""); sub(/ +#.*$/,""); print; exit }' "$INV_HOSTS"
}

cmd_node() {
  local sub="${1:-}" host="${2:-}"
  case "$sub" in
    plan) ;;
    prepare) shift 2 || true; stage_check_host "$host"; stage_prepare "$host" "$@"; return ;;
    verify)  shift 2 || true; stage_check_host "$host"; stage_verify "$host" "$@"; return ;;
    join) die "node join 还没实现（docs/17）。加节点的步骤在 infra/k8s/cluster/kubeadm-join.md。" ;;
    *) die "用法：node plan|verify <主机> [阶段] | node prepare <主机> <阶段>。主机名见 hosts，阶段见 node plan s2。" ;;
  esac
  local role; role="$(host_field "$host" role)"
  [[ -n "$role" ]] || die "inventory/hosts.yaml 里没有主机：${host:-（空）}"
  local addr; addr="$(host_field "$host" lan_ip)"; [[ -n "$addr" ]] || addr="$(host_field "$host" public_ip)"
  echo "${B}$host${O}  角色 $role  地址 ${addr:-未登记}  系统 $(host_field "$host" os)"
  local step=0; s() { step=$((step+1)); echo "  $step. $*"; }
  case "$role" in
    l1) echo "  这是现役的旧集群。本工程不对它做任何准备或加入操作（docs/16）。"; return 0 ;;
    storage) echo "  存储设备，不由脚本配置。"; return 0 ;;
  esac
  if [[ "$role" == control ]]; then
    echo "  控制面按阶段做，每个阶段一条命令做、一条命令验（docs/35）："
    stage_plan "$host"; return 0
  fi
  echo "${D}共同步骤${O}"
  s "主机名、时间同步、内核参数"
  s "磁盘：按 docs/16 分卷（etcd 单独的卷）"
  [[ "$role" == control || "$role" == node ]] && s "挂载 NAS，kubelet 依赖该挂载（docs/14）"
  s "隧道：qp-tunnel-cli 或 WireGuard（docs/08、docs/17）"
  echo "${D}角色 $role${O}"
  case "$role" in
    node)
      s "containerd、kubeadm v1.36"
      s "kubeadm join（infra/k8s/cluster/kubeadm-join.md）"
      s "有 GPU：驱动、设备插件、标签 ladder2/gpu=true"
      s "宿主机 Nginx 和边缘 upstream 加上这台" ;;
    site)
      s "Docker 和 Compose"
      s "部署 sites/<名字>/ 下的 Compose、Nginx、同步任务（docs/17）"
      s "内网侧只对它的隧道地址开放登记过的端口" ;;
    edge)
      s "Nginx、证书"
      s "WireGuard 中继，内网服务器各加一个 peer"
      s "DNS 加记录（docs/17：不要在入口前面再放主控）" ;;
    *) echo "  未知角色：$role" ;;
  esac
  echo "${D}这只是计划。没有连接 $host，也没有执行任何步骤。${O}"
}

cmd_backup() {
  local sub="${1:-plan}"
  [[ "$sub" == plan ]] || die "backup $sub 还没实现（docs/19）。现在只有 backup plan。"
  local f="inventory/backup.yaml"
  echo "${B}存放位置${O}"
  awk '/^targets:/{t=1;next} /^[a-z]/{t=0} t && NF{sub(/^  /,"  "); print}' "$f"
  echo "${B}时间${O}"
  awk '/^schedule:/{t=1;next} /^[a-z]/{t=0} t && NF{print}' "$f"
  echo "${B}备份项${O}"
  awk '/^items:/{t=1;next} /^[a-z]/{t=0} t && NF{
        name=$1; sub(":","",name); host=$0; sub(/.*host: */,"",host); sub(/,.*/,"",host)
        what=$0; sub(/.*what: */,"",what); sub(/ *}$/,"",what)
        mark=(what ~ /待确认/) ? "  ← 待确认，不会执行" : ""
        printf "  %-18s %-3s %s%s\n", name, host, what, mark }' "$f"
  echo "${B}不备份${O}"
  awk '/^excluded:/{t=1;next} /^[a-z]/{t=0} t && NF{print}' "$f"
  echo "${D}这只是计划。backup run 还没实现。${O}"
}

DISK_LOG="${LADDER2_STATE_DIR:-$HOME/.local/state/de-ladder2}/disk.tsv"

cmd_disk() {
  local sub="${1:-}"
  case "$sub" in
    record)
      mkdir -p "$(dirname "$DISK_LOG")"; chmod 700 "$(dirname "$DISK_LOG")"
      local now host; now="$(date +%s)"; host="$(hostname -s)"
      # 只记真实文件系统。NFS 用 hard 挂载，NAS 不可达时 df 会挂住，所以加超时。
      { if command -v timeout >/dev/null; then timeout 20 df -Pk; else df -Pk; fi; } 2>/dev/null \
        | awk -v t="$now" -v h="$host" 'NR>1 && $1 !~ /^(tmpfs|devtmpfs|overlay|shm|map|devfs)/ && $6 !~ /^\/(run|sys|dev|proc|System|private)/ {
            print t "\t" h "\t" $6 "\t" $2 "\t" $3 }' >> "$DISK_LOG"
      echo "已记录到 $DISK_LOG（$(grep -c "^$now" "$DISK_LOG") 个挂载点）" ;;
    trend)
      [[ -s "$DISK_LOG" ]] || die "还没有记录。先在服务器上每天运行 disk record。"
      printf "${B}%-14s %-12s %8s %6s %12s %14s${O}\n" 主机 挂载点 容量G 已用% 每天增长G 到80%还有
      awk -F'\t' '{ k=$2 "\t" $3
          if(!(k in t0)){ t0[k]=$1; u0[k]=$5 }
          t1[k]=$1; u1[k]=$5; sz[k]=$4 }
        END{ for(k in t1){ split(k,a,"\t"); days=(t1[k]-t0[k])/86400
            pct=100*u1[k]/sz[k]
            if(days<1){ rate="—"; left="记录不足一天" }
            else { r=(u1[k]-u0[k])/days/1048576; rate=sprintf("%.1f",r)
                   room=(sz[k]*0.8-u1[k])/1048576
                   left=(r<=0)?"没有增长":(room<=0?"已超过":sprintf("%.0f 天",room/r)) }
            printf "%-14s %-12s %8.0f %5.0f%% %12s %14s\n", a[1], a[2], sz[k]/1048576, pct, rate, left } }' "$DISK_LOG" | sort
      echo "${D}按第一条和最后一条记录算的平均值。记录不到两周时只能看个大概（docs/20）。${O}" ;;
    *) die "用法：disk record | disk trend" ;;
  esac
}

cmd_diagrams() {
  local ARCHIFY_BIN="${ARCHIFY_BIN:-$HOME/.local/share/archify/archify/bin/archify.mjs}"
  [[ -f "$ARCHIFY_BIN" ]] || die "找不到 archify：$ARCHIFY_BIN。安装方法见 docs/13。"
  local f name type out n=0
  for f in docs/atlas/*.json design/architecture/*.json; do
    [[ -e "$f" ]] || continue
    [[ "$f" == *.delivery.json || "$f" == *.visual-check.json || "$f" == *.delivery-pending.json ]] && continue
    name="$(basename "$f")"; type="${name%.json}"; type="${type##*.}"; out="$(dirname "$f")/${name%."$type".json}.html"
    [[ -z "${1:-}" || "$name" == "$1"* ]] || continue
    echo "▶ $f → $out"
    node "$ARCHIFY_BIN" deliver "$type" "$f" "$out" --quality showcase --repo-root "$ROOT" \
      || die "生成失败：$name"
    n=$((n+1))
  done
  (( n )) || echo "docs/atlas 和 design/architecture 里没有匹配的 <名>.<类型>.json 源文件。"
}

# ---------- probe ----------
# 链路探测（docs/26）。只发 GET 请求，不改任何东西。不通就说不通并返回非零。

INV_PROBES="${LADDER2_PROBES:-inventory/probes.yaml}"   # LADDER2_PROBES 只给本机测试脚本用

probe_field() { # probe_field <链路> <字段>
  awk -v r="$1" -v f="$2" '
    /^routes:/{inr=1;next} /^[a-z_]+:/{inr=0}
    inr && /^  [A-Za-z0-9_-]+:[ ]*$/{cur=$1; sub(":","",cur); next}
    inr && cur==r && $1==f":"{ $1=""; sub(/^ +/,""); sub(/ +#.*$/,""); print; exit }' "$INV_PROBES"
}

probe_names() {
  awk '/^routes:/{inr=1;next} /^[a-z_]+:/{inr=0} inr && /^  [A-Za-z0-9_-]+:[ ]*$/{n=$1; sub(":","",n); print n}' "$INV_PROBES"
}

probe_once() { # probe_once <地址> <Host 头，可空> <请求编号> → "状态码 dns tcp tls wait recv total"，单位毫秒
  local url="$1" host="$2" id="$3"
  local args=(-sS -o /dev/null --max-time "${PROBE_TIMEOUT:-10}" -H "X-Request-Id: $id")
  [[ -n "$host" ]] && args+=(-H "Host: $host")
  curl "${args[@]}" -w '%{http_code} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_pretransfer} %{time_starttransfer} %{time_total}\n' "$url" 2>/dev/null \
    | awk '{ tls=($4>0)?($4-$3):0
             printf "%s %.1f %.1f %.1f %.1f %.1f %.1f\n", $1, $2*1000, ($3-$2)*1000, tls*1000, ($6-$5)*1000, ($7-$6)*1000, $7*1000 }'
}

probe_median() { # probe_median <地址> <Host> <次数> <编号> → 合计耗时居中的那一次，末尾加成功次数；全部不通时返回非零
  local url="$1" host="$2" n="$3" id="$4" i out=""
  for ((i=0; i<n; i++)); do out+="$(probe_once "$url" "$host" "$id" || true)"$'\n'; done
  printf '%s' "$out" | awk '$1!="000" && NF==7' | sort -k7,7n \
    | awk '{l[NR]=$0} END{ if (NR==0) exit 1; print l[int((NR+1)/2)], NR }'
}

probe_header() {
  printf "  ${B}%-11s %4s %8s %8s %8s %8s %8s %9s  %s${O}\n" HOP CODE DNS TCP TLS WAIT RECV TOTAL OK
}

PROBE_TOTAL=""
probe_row() { # probe_row <标签> <地址> <Host> <次数> <编号>；结果的合计耗时放进 PROBE_TOTAL
  local label="$1" r
  PROBE_TOTAL=""
  if r="$(probe_median "$2" "$3" "$4" "$5")"; then
    # shellcheck disable=SC2086
    printf "  %-11s %4s %8s %8s %8s %8s %8s %9s  %s/%s\n" "$label" $r "$4"
    PROBE_TOTAL="$(awk '{print $7}' <<<"$r")"
  else
    printf "  %-11s ${R}不通${O}（%s 次都没有得到响应）  %s\n" "$label" "$4" "$2"
    FAILED=1
  fi
}

probe_legend() {
  echo "${D}  单位毫秒，取 ${1} 次里合计居中的一次。DNS 解析 / TCP 建连 / TLS 握手 / WAIT 等首字节 / RECV 传输。${O}"
  echo "${D}  请求编号 ${2}（各层访问日志里用它查这几次请求）。${O}"
}

cmd_probe() {
  local sub="${1:-}"; shift || true
  local n="${PROBE_COUNT:-5}" id
  id="probe-$(date +%Y%m%d%H%M%S)-$$"
  case "$sub" in
    url)
      command -v curl >/dev/null || die "需要 curl"
      local url="${1:-}" host=""; shift || true
      [[ -n "$url" ]] || die "用法：probe url <地址> [--host <域名>]"
      while (( $# )); do
        case "$1" in --host) host="${2:-}"; shift 2 || true ;; *) die "未知参数：$1" ;; esac
      done
      probe_header
      probe_row url "$url" "$host" "$n" "$id"
      probe_legend "$n" "$id" ;;
    list)
      local r
      while read -r r; do
        printf "  %-16s %s%s  %s\n" "$r" "$(probe_field "$r" host)" "$(probe_field "$r" path)" "${D}$(probe_field "$r" what)${O}"
      done < <(probe_names) ;;
    route)
      command -v curl >/dev/null || die "需要 curl"
      local name="${1:-}" host path hop base label
      [[ -n "$name" ]] || die "用法：probe route <名字>。probe list 看有哪些。"
      path="$(probe_field "$name" path)"; host="$(probe_field "$name" host)"
      [[ -n "$path" ]] || die "inventory/probes.yaml 里没有链路 $name，或者它没有 path"
      local t_edge="" t_host_nginx="" t_gateway="" t_service=""
      echo "${B}$name${O}  $host$path"
      probe_header
      for hop in edge host_nginx gateway service; do
        base="$(probe_field "$name" "$hop")"; label="${hop//_/-}"
        if [[ -z "$base" || "$base" == *待确认* ]]; then
          printf "  %-11s ${Y}未登记${O}\n" "$label"; continue
        fi
        probe_row "$label" "$base$path" "$host" "$n" "$id"
        printf -v "t_$hop" '%s' "$PROBE_TOTAL"
      done
      probe_legend "$n" "$id"
      echo "${B}各层自己的开销${O}${D}（相邻两行 TOTAL 之差，估算；两行都测到才有）${O}"
      probe_diff "公网 + Domestic + 隧道" "$t_edge" "$t_host_nginx"
      probe_diff "host-nginx" "$t_host_nginx" "$t_gateway"
      probe_diff "Gateway" "$t_gateway" "$t_service"
      echo "${D}  edge 那一行是从本机出公网再绕回来，包含本机自己的出网路径。${O}" ;;
    wg)
      command -v wg >/dev/null || die "UNKNOWN：这台机器没有 wg 命令"
      local out now; now="$(date +%s)"
      out="$(wg show all latest-handshakes 2>/dev/null)" || die "UNKNOWN：读不到 WireGuard 状态（通常需要 root）"
      [[ -n "$out" ]] || die "UNKNOWN：没有 WireGuard 接口或对端"
      awk -v now="$now" '{
            age=($3>0)?now-$3:-1
            st=(age<0)?"从未握手":(age>180)?"超过 3 分钟没有握手":"正常"
            printf "  %-10s %.16s…  %8s  %s\n", $1, $2, (age<0?"-":age"s"), st
            if (st!="正常") bad=1 } END{ exit bad }' <<<"$out" || FAILED=1
      echo "${D}  没有流量的对端握手时间变长是正常的；有流量还超过 3 分钟才算不通（docs/24）。${O}" ;;
    *) die "用法：probe url <地址> [--host <域名>] | probe list | probe route <名字> | probe wg" ;;
  esac
  if (( FAILED )); then exit 1; fi
}

probe_diff() { # probe_diff <名字> <外层合计> <里层合计>
  if [[ -n "$2" && -n "$3" ]]; then
    printf "  %-24s %8s\n" "$1" "$(awk -v a="$2" -v b="$3" 'BEGIN{printf "%.1f", a-b}')"
  else
    printf "  %-24s %8s\n" "$1" "-"
  fi
}

# ---------- design ----------
# 查看设计文档和架构图的站点（docs/31、32）：design/ 下的首页、演变时间线和 Archify 图，打包成一个 Nginx 镜像。
# 它是本工程的工具，不属于 L2 架构：不登记到 inventory，不接 host-nginx 和 Gateway，版本号在 design/deploy/design.env。

DESIGN_BUILD="design/.build"
DESIGN_ENV="design/deploy/design.env"

design_stage() { # 把站点需要的文件组装到 design/.build/html
  local out="$DESIGN_BUILD/html" f href missing=0
  rm -rf "$DESIGN_BUILD"
  mkdir -p "$out/diagrams" "$out/atlas" "$out/ui"
  cp design/site/index.html design/site/timeline.json "$out/"
  cp console/ui-design/dist/tokens.css "$out/ui/"
  for f in design/architecture/*.html; do [[ -e "$f" ]] && cp "$f" "$out/diagrams/"; done
  for f in docs/atlas/*.html; do [[ -e "$f" && "$(basename "$f")" != index.html ]] && cp "$f" "$out/atlas/"; done
  cp design/deploy/default.conf.template "$DESIGN_BUILD/"
  local rev="未提交"
  rev="$(git rev-parse --short HEAD 2>/dev/null || echo 未提交)"
  [[ -n "$(git status --porcelain -- design docs/atlas 2>/dev/null)" ]] && rev="$rev（有未提交的改动）"
  printf '{"built_at":"%s","revision":"%s"}\n' "$(date '+%Y-%m-%d %H:%M')" "$rev" > "$out/build.json"
  # timeline.json 里引用的每一张图都要在站点里
  while read -r href; do
    [[ -f "$out/$href" ]] || { echo "  ${R}✗${O} timeline.json 引用了不存在的图：$href" >&2; missing=1; }
  done < <(grep -oE '"href": *"[^"]+"' design/site/timeline.json | sed -E 's/.*"([^"]+)"$/\1/')
  (( missing == 0 )) || die "站点组装失败。先 ./scripts/manage.sh diagrams 生成图，或改 timeline.json。"
  echo "  ${G}✓${O} 站点已组装到 $out（$(find "$out" -name '*.html' | wc -l | tr -d ' ') 个页面）"
}

design_need_docker() {
  command -v docker >/dev/null || die "UNKNOWN：这台机器没有 docker"
  docker info >/dev/null 2>&1 || die "UNKNOWN：连不上 Docker（没启动，或当前用户没有权限）"
}

# PROXY=http://127.0.0.1:7788：内网服务器出网走 Internal 的出网代理（qp-tunnel-cli 的 7788 实例）。
# 两件事分开：
#   拉基础镜像  是 Docker 守护进程做的，只认守护进程自己的代理配置，命令行传不进去。
#              这里不改守护进程（改了要重启 docker.service，同机的 Compose 应用会跟着重启），只检查并说明。
#   RUN 步骤    用 --build-arg 传进去；代理在本机回环地址时构建要用宿主机网络才连得上。
DESIGN_PROXY_ARGS=()
design_pull_help() {
  printf '\n  任选一个办法：\n'
  printf '  1. 让守护进程走代理：sudo qp-tunnel-cli docker-build-proxy on（会重启 docker.service，同机的 Compose 应用会跟着重启），拉完可以 off\n'
  printf '  2. 在能联网的机器上 docker pull %s && docker save %s | gzip > base.tar.gz，拷过来 gunzip -c base.tar.gz | docker load\n' "$1" "$1"
  printf '  3. 在开发机上 design build、design export，把整个站点镜像拷过来'
}
design_proxy_prepare() { # design_proxy_prepare <基础镜像>
  local img="$1" dp
  DESIGN_PROXY_ARGS=()
  if [[ -n "${PROXY:-}" ]]; then
    local np="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8"
    DESIGN_PROXY_ARGS+=(--build-arg "HTTP_PROXY=$PROXY" --build-arg "HTTPS_PROXY=$PROXY" --build-arg "NO_PROXY=$np"
                        --build-arg "http_proxy=$PROXY" --build-arg "https_proxy=$PROXY" --build-arg "no_proxy=$np")
    [[ "$PROXY" == *://127.0.0.1:* || "$PROXY" == *://localhost:* ]] && DESIGN_PROXY_ARGS+=(--network host)
    echo "  构建步骤走代理 $PROXY"
  fi
  if docker image inspect "$img" >/dev/null 2>&1; then
    echo "  基础镜像 $img 已在本机，不用拉"
    return 0
  fi
  dp="$(docker info --format '{{.HTTPSProxy}}' 2>/dev/null || true)"
  if [[ -n "${PROXY:-}" && -z "$dp" ]]; then
    die "本机没有基础镜像 $img，而 Docker 守护进程没有配置代理：拉镜像不会走 $PROXY。$(design_pull_help "$img")"
  fi
  if [[ -n "${PROXY:-}" && -n "$dp" && "$dp" != *"${PROXY#*://}"* ]]; then
    warn "Docker 守护进程拉镜像用的代理是 $dp，不是 $PROXY"
  fi
  echo "  拉基础镜像 $img${dp:+（守护进程的代理：$dp）}"
  docker pull "$img" || die "拉不到基础镜像 $img。$(design_pull_help "$img")"
}

# 网络模式（docs/31）。都不新建 Docker 网络：s1 上 Docker 找不到不重叠的地址池，建网络会失败。
#   host    Linux 服务器默认。Nginx 直接在宿主机上监听 DESIGN_BIND:端口，不加 iptables 规则
#   bridge  macOS 默认。Docker Desktop 的 host 网络不通到 Mac 本机，只能用默认 bridge 加端口映射
# DESIGN_NETWORK=host|bridge 可以强制指定。监听地址 DESIGN_BIND 默认 0.0.0.0（design.env，用户 2026-11-17 决定），可用环境变量覆盖。
design_network() {
  if [[ -n "${DESIGN_NETWORK:-}" ]]; then
    [[ "$DESIGN_NETWORK" == host || "$DESIGN_NETWORK" == bridge ]] || die "DESIGN_NETWORK 只能是 host 或 bridge"
    echo "$DESIGN_NETWORK"
  elif [[ "$(uname -s)" == Darwin ]]; then echo bridge
  else echo host; fi
}

design_compose() {
  # shellcheck source=/dev/null
  source "$DESIGN_ENV"
  local mode; mode="$(design_network)"
  DESIGN_IMAGE="ladder2-design:latest" DESIGN_PORT="${DESIGN_PORT:-18310}" DESIGN_BIND="${DESIGN_BIND:-0.0.0.0}" \
    docker compose -p ladder2-design -f design/deploy/compose.yml -f "design/deploy/compose.$mode.yml" "$@"
}

design_reach_hint() { # design_reach_hint <监听地址> <端口>：从别的机器怎么打开；防火墙只查不改
  local bind="$1" port="$2" ips="" ip
  if [[ "$bind" == 127.0.0.1 ]]; then
    echo "  ${D}只听本机回环。从自己电脑看：ssh -L $port:127.0.0.1:$port <这台机器>，再打开 http://127.0.0.1:$port/${O}"
    return 0
  fi
  if [[ "$bind" == 0.0.0.0 ]]; then
    if hostname -I >/dev/null 2>&1; then ips="$(hostname -I)"
    elif command -v ipconfig >/dev/null; then ips="$(ipconfig getifaddr en0 2>/dev/null || true)"; fi
    echo "  听所有网卡（包括 WireGuard、OpenVPN 这类隧道网卡）。从其他机器打开："
    for ip in $ips; do [[ "$ip" == *:* ]] || echo "    http://$ip:$port/"; done
  else
    echo "  从其他机器打开：http://$bind:$port/"
  fi
  # 防火墙：只查询，不放行。放行是改 iptables，由人决定（CLAUDE.md）
  if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
    if firewall-cmd --query-port="$port/tcp" >/dev/null 2>&1; then ok "firewalld 已放行 $port/tcp"
    else
      warn "firewalld 在运行，没有放行 $port/tcp，其他机器可能打不开。要放行由你执行这两条（第一条马上生效，第二条重启后保留）："
      echo "      firewall-cmd --add-port=$port/tcp"
      echo "      firewall-cmd --permanent --add-port=$port/tcp"
      # 不要 reload：s1 上 firewalld reload 会清掉 hostPort 的转发规则，要等 Pod 重建才恢复
      # （L1 mx-launcher/deploy/k8s/internal-shadow/15-dns-control-target.yaml 的注释）
      echo "  ${R}不要执行 firewall-cmd --reload${O}：在跑着 Kubernetes 的机器（比如 s1）上，它会清掉 hostPort 的转发规则，相关服务要等 Pod 重建才恢复。"
    fi
  elif command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw status 2>/dev/null | grep -qE "^$port(/tcp)? +ALLOW"; then ok "ufw 已放行 $port/tcp"
    else warn "ufw 在运行，没有放行 $port/tcp，其他机器可能打不开。要放行由你执行：ufw allow $port/tcp"; fi
  fi
}

design_port_free() { # design_port_free <端口>：host 网络下启动前确认没人占用
  local port="$1" used
  if docker inspect -f '{{.State.Running}}' ladder2-design 2>/dev/null | grep -q true; then return 0; fi   # 是它自己在用
  if ! command -v ss >/dev/null; then warn "没有 ss 命令，跳过端口检查"; return 0; fi
  used="$(ss -ltnpH "sport = :$port" 2>/dev/null || true)"
  [[ -z "$used" ]] || die "端口 $port 已经有程序在监听，不启动：
$used
  换端口改 design/deploy/design.env 的 DESIGN_PORT，再 design up。"
}

cmd_design() {
  local sub="${1:-}"; shift || true
  # shellcheck source=/dev/null
  source "$DESIGN_ENV"
  local port="${DESIGN_PORT:-18310}"
  case "$sub" in
    stage) design_stage ;;
    serve)
      design_stage
      local p="${1:-8310}"
      echo "  预览：http://127.0.0.1:$p/   （Ctrl-C 结束）"
      python3 -m http.server "$p" --bind 127.0.0.1 --directory "$DESIGN_BUILD/html" ;;
    build)
      design_need_docker
      design_stage
      local tag; tag="$(date +%Y%m%d-%H%M%S)"
      design_proxy_prepare "$DESIGN_NGINX_IMAGE"
      docker build ${DESIGN_PROXY_ARGS[@]+"${DESIGN_PROXY_ARGS[@]}"} --build-arg "NGINX_IMAGE=$DESIGN_NGINX_IMAGE" -f design/deploy/Dockerfile \
        -t "ladder2-design:$tag" -t ladder2-design:latest "$DESIGN_BUILD"
      echo "  ${G}✓${O} 镜像 ladder2-design:$tag（同时标为 latest）"
      echo "  只是打好了镜像，还没有运行。启动：./scripts/manage.sh design up" ;;
    up)
      design_need_docker
      docker image inspect ladder2-design:latest >/dev/null 2>&1 || die "没有镜像 ladder2-design:latest。先 design build，或 docker load 导入。"
      docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' ladder2-design:latest | grep -q '^DESIGN_LISTEN=' \
        || die "ladder2-design:latest 是旧版本的镜像（监听地址写死在镜像里）。先 git pull，再 design build。"
      local mode bind="${DESIGN_BIND:-0.0.0.0}" probe i
      mode="$(design_network)"
      probe="$bind"
      if [[ "$bind" == 0.0.0.0 ]]; then probe=127.0.0.1; fi   # 听所有网卡时从本机回环探测
      if [[ "$mode" == host ]]; then design_port_free "$port"; fi
      echo "  网络：$mode；监听 $bind:$port。不新建 Docker 网络$([[ "$mode" == host ]] && echo "，不加 iptables 规则")"
      design_compose up -d --pull never
      for i in 1 2 3 4 5 6 7 8 9 10; do
        curl -fsS --max-time 2 "http://$probe:$port/healthz" >/dev/null 2>&1 && break
        sleep 1
      done
      if curl -fsS --max-time 2 "http://$probe:$port/healthz" >/dev/null 2>&1; then
        echo "  ${G}✓${O} 已启动：http://$probe:$port/"
        design_reach_hint "$bind" "$port"
      else
        docker logs --tail 20 ladder2-design 2>&1 | sed 's/^/    /'
        die "容器起来了，但 http://$probe:$port/healthz 不通。上面是容器最后 20 行日志。"
      fi ;;
    stop)
      design_need_docker
      design_compose stop ;;
    status)
      design_need_docker
      local st; st="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' ladder2-design 2>/dev/null)" \
        || { echo "  未部署（这台机器上没有 ladder2-design 容器）"; return 0; }
      local addr net
      net="$(docker inspect -f '{{.HostConfig.NetworkMode}}' ladder2-design)"
      addr="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' ladder2-design | sed -n 's/^DESIGN_LISTEN=//p')"
      # host 网络时 DESIGN_LISTEN 就是宿主机上的地址；bridge 时它只是容器里的端口，宿主机上的地址看端口映射
      if [[ -n "$addr" && "$addr" != *:* ]]; then addr="$(docker port ladder2-design "$addr/tcp" 2>/dev/null | head -1)"; fi
      [[ -n "$addr" ]] || addr="127.0.0.1:$port"
      if [[ "$addr" == 0.0.0.0:* ]]; then addr="127.0.0.1:${addr#0.0.0.0:}"; fi   # 听所有网卡时从本机回环探测
      echo "  容器：$st；网络：$net；镜像：$(docker inspect -f '{{.Config.Image}}' ladder2-design)"
      if curl -fsS --max-time 3 "http://$addr/healthz" >/dev/null 2>&1; then ok "http://$addr/healthz"
      else bad "http://$addr/healthz 不通"; fi
      if (( FAILED )); then exit 1; fi ;;
    export)
      design_need_docker
      docker image inspect ladder2-design:latest >/dev/null 2>&1 || die "没有镜像 ladder2-design:latest。先 design build。"
      local f="$DESIGN_BUILD/ladder2-design-$(date +%Y%m%d-%H%M%S).tar.gz"
      mkdir -p "$DESIGN_BUILD"
      docker save ladder2-design:latest | gzip > "$f"
      echo "  ${G}✓${O} $f（$(du -h "$f" | cut -f1)）"
      echo "  在服务器上：gunzip -c <文件> | docker load，然后 ./scripts/manage.sh design up" ;;
    *) die "用法：design stage | serve [端口] | build | up | stop | status | export（docs/31、32）" ;;
  esac
}

# s2 的落地阶段（node prepare / verify）和压测（docs/35）
# shellcheck source=lib/stages.sh
source "$ROOT/scripts/lib/stages.sh"
# shellcheck source=lib/loadtest.sh
source "$ROOT/scripts/lib/loadtest.sh"
# shellcheck source=lib/apps.sh
source "$ROOT/scripts/lib/apps.sh"

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    help|-h|--help) usage ;;
    list) cmd_list ;;
    hosts) cmd_hosts ;;
    docs) cmd_docs ;;
    check) cmd_check ;;
    doctor) cmd_doctor ;;
    k8s) cmd_k8s "$@" ;;
    l1) cmd_l1 "$@" ;;
    run) cmd_run "$@" ;;
    app) cmd_app "$@" ;;
    image) cmd_image "$@" ;;
    secret) cmd_secret "$@" ;;
    node) cmd_node "$@" ;;
    backup) cmd_backup "$@" ;;
    disk) cmd_disk "$@" ;;
    diagrams) cmd_diagrams "$@" ;;
    probe) cmd_probe "$@" ;;
    loadtest) cmd_loadtest "$@" ;;
    design) cmd_design "$@" ;;
    *) usage; die "未知命令：$cmd" ;;
  esac
}
main "$@"
