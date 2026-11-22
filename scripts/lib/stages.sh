# s2（以及以后的控制面、节点）的落地阶段：每个阶段一条命令做、一条命令验（docs/35）。
# 被 scripts/manage.sh source，不单独运行。用到 manage.sh 里的 host_field、need_context、confirm、die、颜色变量。
#
#   node plan    <主机>                          阶段表：做什么、怎么做、怎么验
#   node prepare <主机> <阶段> [--context 名字]   做一个阶段。一次一个，没有"全部"
#   node verify  <主机> [阶段] [--context 名字]   只读。逐项 ✓ / ✗ / UNKNOWN，有 ✗ 或 UNKNOWN 就返回非零

STAGES=(host disk nas runtime cluster network backup metrics gateway postgres host-nginx sample loadtest edge)

stage_desc() {
  case "$1" in
    host)       echo "系统参数：k8s-api 名字、swap、内核模块和参数、时间同步" ;;
    disk)       echo "分卷：/data、/var/lib/etcd 单独的卷（docs/16）" ;;
    nas)        echo "挂 NAS；kubelet 等 NAS 挂好再启动" ;;
    runtime)    echo "containerd、kubeadm / kubelet / kubectl $K8S_MINOR" ;;
    cluster)    echo "kubeadm init，context 叫 ladder2" ;;
    network)    echo "flannel、CoreDNS、local-path（默认存储类 local-retain）" ;;
    backup)     echo "etcd 快照和 pki 每天 02:00 写 NAS（先于任何业务）" ;;
    metrics)    echo "metrics-server（HPA 和 kubectl top 要用）" ;;
    gateway)    echo "Gateway public :$GATEWAY_PUBLIC_NODEPORT、internal :$GATEWAY_INTERNAL_NODEPORT" ;;
    postgres)   echo "CloudNativePG，pg-common" ;;
    host-nginx) echo "s2 的宿主机 Nginx，:80" ;;
    sample)     echo "样板服务：各层都通，网关认对客户端地址" ;;
    loadtest)   echo "1000 QPS：service、两个 Gateway、host-nginx、pg-common" ;;
    edge)       echo "Domestic → WireGuard → s2（手工，碰共用的边缘）" ;;
    *) return 1 ;;
  esac
}

# host：在目标机器上以 root 跑角色脚本；cluster：带 --context 往集群装；manual：人做，脚本只验
stage_kind() {
  case "$1" in
    host|nas|runtime|cluster|backup|host-nginx) echo host ;;
    network|metrics|gateway|postgres|sample|loadtest) echo cluster ;;
    disk|edge) echo manual ;;
  esac
}

stage_script() {
  case "$1" in
    host) echo common/10-host.sh ;; nas) echo common/20-nas.sh ;;
    runtime) echo control/30-runtime.sh ;; cluster) echo control/40-cluster.sh ;;
    backup) echo control/50-backup.sh ;; host-nginx) echo control/60-host-nginx.sh ;;
  esac
}

stage_how() { # stage_how <主机> <阶段>
  local h="$1"
  case "$(stage_kind "$2")" in
    host)    echo "sudo ./scripts/manage.sh node prepare $h $2" ;;
    cluster) echo "./scripts/manage.sh node prepare $h $2 --context ladder2" ;;
    manual)  echo "手工（docs/35）" ;;
  esac
}

local_ips() {
  if command -v ip >/dev/null; then ip -4 -o addr show 2>/dev/null | awk '{split($4,a,"/"); print a[1]}'
  else ifconfig 2>/dev/null | awk '$1=="inet"{print $2}'; fi
}

is_s1_here() { local s1ip; s1ip="$(host_field s1 lan_ip)"; [[ -n "$s1ip" ]] && local_ips | grep -qx "$s1ip"; }

stage_check_host() { # 只有 control / node 角色走这套阶段
  local role; role="$(host_field "$1" role)"
  [[ -n "$role" ]] || die "inventory/hosts.yaml 里没有主机：${1:-（空）}"
  case "$role" in
    control|node) ;;
    l1) die "$1 是现役的 L1。本工程不对它做任何准备或加入操作（docs/16）。" ;;
    *) die "$1 的角色是 $role，不走这套阶段（只给 control / node）。node plan $1 看它的步骤。" ;;
  esac
}

# ---------- plan ----------

stage_plan() {
  local h="$1" s i=0
  for s in "${STAGES[@]}"; do
    i=$((i+1))
    printf "  ${B}%2s %-11s${O}%s\n" "$i" "$s" "$(stage_desc "$s")"
    printf "     %-11s${D}%s${O}\n" "" "$(stage_how "$h" "$s")"
  done
  echo
  echo "  每做完一个：./scripts/manage.sh node verify $h <阶段>；全部看一遍：./scripts/manage.sh node verify $h"
  echo "  ${D}按顺序做。每个阶段都可以重复执行，已经是目标状态就不动。设了 PROXY 时下载走代理。完整说明见 docs/35。${O}"
}

# ---------- prepare ----------

stage_prepare() {
  local h="$1" s="${2:-}"; shift 2 || true
  [[ -n "$s" ]] || die "用法：node prepare $h <阶段>。一次一个阶段，没有“全部”。阶段：${STAGES[*]}"
  stage_desc "$s" >/dev/null || die "没有阶段 $s。阶段：${STAGES[*]}"
  is_s1_here && die "这台是 s1。不在 s1 上做任何准备（CLAUDE.md 硬约束）。"
  case "$(stage_kind "$s")" in
    host)
      local lan; lan="$(host_field "$h" lan_ip)"
      local_ips | grep -qx "$lan" || die "阶段 $s 要在 $h 本机上执行（本机没有地址 $lan）。登录 $h：sudo ./scripts/manage.sh node prepare $h $s"
      [[ $EUID -eq 0 ]] || die "阶段 $s 要 root：sudo ./scripts/manage.sh node prepare $h $s"
      echo "${B}$h · $s${O}  $(stage_desc "$s")"
      LADDER2_HOST="$h" PROXY="${PROXY:-}" bash "$ROOT/scripts/roles/$(stage_script "$s")"
      echo "${G}完成。${O}验证：./scripts/manage.sh node verify $h $s" ;;
    cluster)
      local ctx; ctx="$(need_context "$@")"
      echo "${B}$h · $s${O}  $(stage_desc "$s")  → 集群 ${B}$ctx${O}"
      case "$s" in
        network)  confirm "这会往集群装 flannel 和 local-path。"
                  PROXY="${PROXY:-}" bash "$K8S/platform/install.sh" flannel "$ctx"
                  PROXY="${PROXY:-}" bash "$K8S/platform/install.sh" local-path "$ctx" ;;
        metrics)  confirm "这会往集群装 metrics-server。"
                  PROXY="${PROXY:-}" bash "$K8S/platform/install.sh" metrics-server "$ctx" ;;
        gateway|postgres)
                  confirm "这会往集群装 $s。"
                  PROXY="${PROXY:-}" bash "$K8S/platform/install.sh" "$s" "$ctx" ;;
        sample)
          kubectl --context "$ctx" apply -f "$ROOT/services/sample/deploy/k8s/platform/namespace.yaml"
          kubectl --context "$ctx" apply -k "$ROOT/services/sample/deploy/k8s/overlays/production"
          kubectl --context "$ctx" -n sample rollout status deployment/sample --timeout=180s ;;
        loadtest)
          # 各层依次压，每层之间停 30 秒让连接和 HPA 回落。任何一层没过，后面的照样跑完，最后一起看
          local r rc=0
          for r in "sample service" "sample gateway" "sample-internal gateway" "sample host-nginx"; do
            set -- $r
            cmd_loadtest run "$1" --hop "$2" --context "$ctx" || rc=1
            sleep 30
          done
          cmd_loadtest pg --context "$ctx" || rc=1
          (( rc == 0 )) || die "有的层没扛住 1000 QPS。上面每层都有数字；loadtest results 看汇总。" ;;
      esac
      echo "${G}完成。${O}验证：./scripts/manage.sh node verify $h $s --context $ctx" ;;
    manual)
      case "$s" in
        disk) die "分卷会清空磁盘，脚本不做。按 docs/16 的分卷表手工分（docs/35 有命令），做完 node verify $h disk。" ;;
        edge) die "边缘 Domestic 和 MX-H2I 共用，脚本不改它。按 docs/35 的“edge”一节手工加 WireGuard 对端和测试域名，做完 node verify $h edge。" ;;
      esac ;;
  esac
}

# ---------- verify ----------

V_OK=0; V_BAD=0; V_UNK=0
vok()  { echo "  ${G}✓${O} $*"; V_OK=$((V_OK+1)); }
vbad() { echo "  ${R}✗${O} $*"; V_BAD=$((V_BAD+1)); }
vunk() { echo "  ${Y}?${O} UNKNOWN：$*"; V_UNK=$((V_UNK+1)); }
vwarn() { echo "  ${Y}!${O} $*"; }
vnote() { echo "    ${D}$*${O}"; }

VHOST=""; VCTX=""; VLAN=""; VCLUSTER=""
kc() { kubectl --context "$VCTX" --request-timeout=10s "$@"; }
v_on_host() { local_ips | grep -qx "$VLAN"; }
v_need_host() { v_on_host && return 0; vunk "要在 $VHOST 本机上运行才查得到（本机没有地址 $VLAN）"; return 1; }
v_need_cluster() { [[ "$VCLUSTER" == yes ]] && return 0; vunk "连不上集群（context ${VCTX}）：$VCLUSTER"; return 1; }
v_http() { # v_http <地址> [Host] → 状态码，不通是 000
  local a=(-s -o /dev/null -w '%{http_code}' --max-time 5)
  [[ -n "${2:-}" ]] && a+=(-H "Host: $2")
  curl "${a[@]}" "$1" 2>/dev/null || true
}
v_said() { if [[ "$1" == 000 ]]; then echo 不通; else echo "返回 $1"; fi; }
v_ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0>=b+0)}'; }

v_host() {
  v_need_host || return 0
  local hn; hn="$(hostname -s)"
  if [[ -n "$hn" && "$hn" != localhost* ]]; then vok "主机名 $hn"; else vbad "主机名还是 $hn（hostnamectl set-hostname）"; fi
  if getent hosts k8s-api.ladder2.internal 2>/dev/null | awk '{print $1}' | grep -qx "$VLAN"; then vok "k8s-api.ladder2.internal → $VLAN"
  else vbad "k8s-api.ladder2.internal 没有指向 $VLAN（/etc/hosts）"; fi
  if [[ -z "$(swapon --show --noheadings 2>/dev/null)" ]]; then vok "swap 已关"; else vbad "swap 没关"; fi
  local kv want name val
  for kv in net.bridge.bridge-nf-call-iptables=1 net.ipv4.ip_forward=1 vm.max_map_count=262144 \
            net.netfilter.nf_conntrack_max=1048576 net.core.somaxconn=65535 net.ipv4.tcp_max_syn_backlog=65535 \
            fs.file-max=2097152 fs.inotify.max_user_instances=8192; do
    name="${kv%%=*}"; want="${kv#*=}"
    val="$(sysctl -n "$name" 2>/dev/null || true)"
    if [[ -z "$val" ]]; then vbad "$name 读不到（模块没加载？）"
    elif v_ge "$val" "$want"; then vok "$name = $val"
    else vbad "$name = $val，要 ≥ $want"; fi
  done
  if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == yes ]]; then vok "时间已同步"
  else vbad "时间没有同步（timedatectl）"; fi
  # Pod / Service 网段不能和这台机器已有的路由重叠（docs/08、docs/41）。Docker 的网桥最常撞上：它的默认地址池含 192.168.0.0/16。
  local clash="" line dest
  while read -r line; do
    dest="${line%% *}"
    [[ "$dest" =~ ^[0-9.]+(/[0-9]+)?$ ]] || continue
    [[ "$line" =~ dev\ (cni0|flannel\.1)( |$) ]] && continue
    if v_cidr_overlap "$dest" "$POD_CIDR" || v_cidr_overlap "$dest" "$SERVICE_CIDR"; then clash+="$line; "; fi
  done < <(ip -4 route 2>/dev/null)
  if [[ -z "$clash" ]]; then vok "没有路由和 Pod 网段 $POD_CIDR、Service 网段 $SERVICE_CIDR 重叠"
  else vbad "有路由和集群网段重叠：$clash"; fi
  vnote "$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-系统未知}")，$(nproc 2>/dev/null) 核，内存 $(free -g 2>/dev/null | awk '/^Mem:/{print $2}')G。核对后写进 inventory/hosts.yaml"
}

v_cidr_range() { # v_cidr_range a.b.c.d[/n] -> "<first> <last>" as integers
  local ip="${1%/*}" n=32 a b c d first size
  [[ "$1" == */* ]] && n="${1#*/}"
  IFS=. read -r a b c d <<<"$ip"
  first=$(( (a << 24) + (b << 16) + (c << 8) + d ))
  size=$(( 1 << (32 - n) ))
  first=$(( first - first % size ))
  echo "$first $(( first + size - 1 ))"
}

v_cidr_overlap() { # true when the two blocks share an address
  local a1 a2 b1 b2
  read -r a1 a2 <<<"$(v_cidr_range "$1")"
  read -r b1 b2 <<<"$(v_cidr_range "$2")"
  (( a1 <= b2 && b1 <= a2 ))
}

v_disk() {
  v_need_host || return 0
  local mp use
  for mp in /data /var/lib/etcd /var/lib/containerd; do
    if mountpoint -q "$mp" 2>/dev/null; then
      use="$(df -P "$mp" | awk 'NR==2{gsub("%","",$5); print $5}')"
      vok "$mp 是单独的卷：$(df -hT "$mp" | awk 'NR==2{print $2, $3}')，已用 ${use}%"
      (( use < 70 )) || vbad "$mp 已用 ${use}%，超过告警线 70%（docs/20）"
    elif [[ "$mp" == /var/lib/containerd ]]; then
      vwarn "$mp 不是单独的卷（docs/16 建议 300G 一卷，不强求）"
    else
      vbad "$mp 不是单独的卷（docs/16 的分卷表）"
    fi
  done
  use="$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')"
  if (( use < 70 )); then vok "/ 已用 ${use}%"; else vbad "/ 已用 ${use}%"; fi
}

v_nas() {
  v_need_host || return 0
  local want have
  want="$(awk '/^hosts:/{h=1} h && /^  nas:/{n=1;next} n && /^  [a-z]/{n=0} n && $1=="fstab:"{g=1;next} g && /^      /{sub(/^ +/,""); o=(o==""?$0:o" "$0);next} g{g=0} END{print o}' "$INV_HOSTS")"
  have="$(awk '$1 !~ /^#/ && $2=="/mnt/nas"' /etc/fstab 2>/dev/null)"
  if [[ -z "$have" ]]; then vbad "/etc/fstab 没有 /mnt/nas"
  elif [[ "$(echo $have)" == "$(echo $want)" ]]; then vok "fstab 和登记的一致"
  else vwarn "fstab 的 /mnt/nas 和 inventory/hosts.yaml 登记的不同：$have"; fi
  if mountpoint -q /mnt/nas 2>/dev/null; then
    if timeout 5 ls /mnt/nas >/dev/null 2>&1; then vok "/mnt/nas 已挂载，5 秒内可读"
    else vbad "/mnt/nas 已挂载但 5 秒内读不出（hard 挂载下 NAS 不可达会挂住）"; fi
  else vbad "/mnt/nas 没有挂载"; fi
  if grep -qs 'RequiresMountsFor=/mnt/nas' /etc/systemd/system/kubelet.service.d/10-requires-nas.conf; then vok "kubelet 等 NAS 挂好再启动"
  else vbad "缺 /etc/systemd/system/kubelet.service.d/10-requires-nas.conf"; fi
}

v_runtime() {
  v_need_host || return 0
  if systemctl is-active -q containerd 2>/dev/null; then vok "containerd 在运行"; else vbad "containerd 没在运行"; fi
  if grep -qs 'SystemdCgroup = true' /etc/containerd/config.toml; then vok "containerd 用 systemd cgroup"
  else vbad "/etc/containerd/config.toml 没有 SystemdCgroup = true"; fi
  local t v vs=()
  for t in kubeadm kubelet kubectl; do
    case "$t" in
      kubeadm) v="$(kubeadm version -o short 2>/dev/null || true)" ;;
      kubelet) v="$(kubelet --version 2>/dev/null | awk '{print $2}' || true)" ;;
      kubectl) v="$(kubectl version --client 2>/dev/null | awk '/Client Version/{print $3}' || true)" ;;
    esac
    if [[ -z "$v" ]]; then vbad "$t 没装"; continue; fi
    vs+=("$v")
    if [[ "$v" == "$K8S_MINOR".* ]]; then vok "$t $v"; else vbad "$t $v，不是 $K8S_MINOR"; fi
    [[ -z "${K8S_VERSION:-}" || "$v" == "$K8S_VERSION" ]] || vbad "$t $v 和 versions.env 的 K8S_VERSION=$K8S_VERSION 不同"
  done
  if (( ${#vs[@]} == 3 )) && [[ "${vs[0]}" == "${vs[1]}" && "${vs[1]}" == "${vs[2]}" ]]; then vok "三个版本一致"
  elif (( ${#vs[@]} == 3 )); then vbad "三个版本不一致：${vs[*]}"; fi
  local held; held="$(apt-mark showhold 2>/dev/null | tr '\n' ' ')"
  if [[ "$held" == *kubeadm* && "$held" == *kubelet* && "$held" == *kubectl* ]]; then vok "已锁定版本（apt-mark hold）"
  else vbad "没有锁定版本，apt upgrade 会把它们升上去"; fi
  if [[ "$(helm version --short 2>/dev/null)" == "$HELM_VERSION"* ]]; then vok "helm $HELM_VERSION"
  else vbad "helm 不是 $HELM_VERSION（$(helm version --short 2>/dev/null || echo 没装)）"; fi
  [[ -f /etc/systemd/system/containerd.service.d/10-ladder2-proxy.conf ]] && vnote "containerd 拉镜像走代理（10-ladder2-proxy.conf）"
  [[ -z "${K8S_VERSION:-}" ]] && vnote "versions.env 的 K8S_VERSION 还空着：补丁版本要和 s1 一致（docs/16）"
  return 0
}

v_cluster() {
  v_need_cluster || return 0
  local server; server="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$VCTX\")].context.cluster}")\")].cluster.server}")"
  vnote "context $VCTX → $server"
  if kc get --raw /readyz >/dev/null 2>&1; then vok "API /readyz"; else vbad "API /readyz 不通"; fi
  local sv; sv="$(kc version -o json 2>/dev/null | awk -F'"' '/"gitVersion"/{v=$4} END{print v}')"
  if [[ "$sv" == "$K8S_MINOR".* ]]; then vok "集群版本 $sv"; else vbad "集群版本 ${sv:-读不到}，不是 $K8S_MINOR"; fi
  local c
  for c in etcd kube-apiserver kube-controller-manager kube-scheduler; do
    if kc -n kube-system get pod -l component="$c" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then vok "$c 在运行"
    else vbad "$c 没在运行"; fi
  done
  local nodes; nodes="$(kc get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status} {end}' 2>/dev/null)"
  vnote "节点：$nodes（装 flannel 之前是 False，正常）"
  if kc get nodes -o jsonpath='{.items[*].spec.taints[*].key}' 2>/dev/null | grep -qw node-role.kubernetes.io/control-plane; then
    vbad "控制面还有污点，业务调度不上来（单节点要去掉）"
  else vok "控制面没有污点"; fi
  # 集群建在哪个地址上：kubeadm 把它写进了 apiserver 的证书、etcd 和 kubelet 的 node-ip，建好以后不能再变（docs/50）
  local nodeip; nodeip="$(kc get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)"
  if [[ -z "$nodeip" ]]; then vunk "读不到节点的 InternalIP"
  elif [[ "$nodeip" == "$VLAN" ]]; then vok "节点地址 $nodeip 和这次的 $VHOST 地址一致"
  else vbad "集群建在 $nodeip 上，这次 $VHOST 的地址是 $VLAN（来自 $(site_lan_source "$VHOST")）。建好以后改地址要重签证书、改 etcd 和 kubelet：先把机器的地址固定回 $nodeip（路由器上做 DHCP 保留），或者确认是这里设错了（docs/50）"; fi
  local mode; mode="$(kc -n kube-system get cm kube-proxy -o jsonpath='{.data.config\.conf}' 2>/dev/null | awk '$1=="mode:"{print $2}')"
  vnote "kube-proxy 模式：${mode:-默认}（host-nginx 转 NodePort 用 LAN 地址，两种模式都行）"
}

v_network() {
  v_need_cluster || return 0
  local r
  r="$(kc -n kube-flannel get ds kube-flannel-ds -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}' 2>/dev/null || true)"
  if [[ -n "$r" && "${r%/*}" == "${r#*/}" && "${r%/*}" != 0 ]]; then vok "flannel $r 就绪"; else vbad "flannel ${r:-没装}"; fi
  if [[ "$(kc get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" =~ ^(True ?)+$ ]]; then vok "节点都 Ready"
  else vbad "有节点不是 Ready"; fi
  r="$(kc -n kube-system get deploy coredns -o jsonpath='{.status.availableReplicas}/{.spec.replicas}' 2>/dev/null || true)"
  if [[ -n "$r" && "${r%/*}" == "${r#*/}" ]]; then vok "CoreDNS $r"; else vbad "CoreDNS ${r:-读不到}"; fi
  r="$(kc -n local-path-storage get deploy local-path-provisioner -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  if [[ "${r:-0}" -ge 1 ]]; then vok "local-path-provisioner 在运行"; else vbad "local-path-provisioner 没在运行"; fi
  if kc -n local-path-storage get cm local-path-config -o jsonpath='{.data.config\.json}' 2>/dev/null | grep -q /data/k8s/storage; then
    vok "卷的数据目录是 /data/k8s/storage"
  else vbad "local-path 的数据目录不是 /data/k8s/storage"; fi
  local rp def
  rp="$(kc get sc local-retain -o jsonpath='{.reclaimPolicy}' 2>/dev/null || true)"
  def="$(kc get sc local-retain -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null || true)"
  if [[ "$rp" == Retain && "$def" == true ]]; then vok "默认存储类 local-retain（Retain：删 PVC 不删数据）"
  else vbad "存储类 local-retain 不对：reclaimPolicy=${rp:-无} 默认=${def:-否}"; fi
}

v_backup() {
  v_need_host || return 0
  if systemctl is-enabled -q ladder2-etcd-backup.timer 2>/dev/null && systemctl is-active -q ladder2-etcd-backup.timer 2>/dev/null; then
    vok "定时器启用，下次 $(systemctl show -p NextElapseUSecRealtime --value ladder2-etcd-backup.timer 2>/dev/null)"
  else vbad "定时器 ladder2-etcd-backup.timer 没启用"; fi
  local res; res="$(systemctl show -p Result --value ladder2-etcd-backup.service 2>/dev/null || true)"
  if [[ "$res" == success ]]; then vok "上一次运行成功"; else vbad "上一次运行结果：${res:-读不到}（journalctl -u ladder2-etcd-backup）"; fi
  if ! timeout 5 ls /mnt/nas >/dev/null 2>&1; then vbad "/mnt/nas 读不出"; return 0; fi
  local last; last="$(ls -d /mnt/nas/backup/ladder2-backup-* 2>/dev/null | sort | tail -1)"
  if [[ -z "$last" ]]; then vbad "NAS 上还没有 ladder2-backup-*"; return 0; fi
  local age=$(( $(date +%s) - $(stat -c %Y "$last") ))
  if (( age < 26*3600 )); then vok "最近一份 $(basename "$last")，$((age/3600)) 小时前"
  else vbad "最近一份 $(basename "$last") 已经 $((age/3600)) 小时，超过 26 小时"; fi
  if [[ -s "$last/cluster/etcd-snapshot.db" && -s "$last/cluster/pki.tar" ]]; then
    if (cd "$last/cluster" && sha256sum -c --quiet SHA256SUMS >/dev/null 2>&1); then vok "快照和 pki 的校验和对得上"
    else vbad "$last/cluster 的校验和对不上"; fi
  else vbad "$last/cluster 缺快照或 pki.tar"; fi
  vnote "pki.tar 含 CA 私钥，没有加密；加密的密钥放哪还没定（docs/15 第 17 项）"
}

v_metrics() {
  v_need_cluster || return 0
  local r; r="$(kc -n kube-system get deploy metrics-server -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  if [[ "${r:-0}" -ge 1 ]]; then vok "metrics-server 在运行"; else vbad "metrics-server 没在运行"; fi
  local top; top="$(kc top node --no-headers 2>/dev/null || true)"
  if [[ -n "$top" ]]; then vok "kubectl top node：$(echo "$top" | awk '{printf "%s CPU %s 内存 %s; ", $1, $3, $5}')"
  else vbad "kubectl top node 没有数（刚装好要等一两分钟）"; fi
}

v_gateway() {
  v_need_cluster || return 0
  local r g st ns svc port
  r="$(kc -n nginx-gateway get deploy -o jsonpath='{range .items[*]}{.status.availableReplicas}/{.spec.replicas} {end}' 2>/dev/null || true)"
  if [[ -n "$r" ]] && ! grep -qE '(^|[^0-9])(/|0/)' <<<"$r"; then vok "NGF 控制面 $r"; else vbad "NGF 控制面 ${r:-没装}"; fi
  for g in public internal; do
    st="$(kc -n gateway get gateway "$g" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)"
    if [[ "$st" == True ]]; then vok "Gateway $g Programmed"; else vbad "Gateway $g 不是 Programmed（${st:-没有}）"; fi
  done
  r="$(kc -n gateway get deploy -o jsonpath='{range .items[*]}{.metadata.name}={.status.availableReplicas}/{.spec.replicas} {end}' 2>/dev/null || true)"
  vnote "数据面：${r:-读不到}"
  for g in "public $GATEWAY_PUBLIC_NODEPORT" "internal $GATEWAY_INTERNAL_NODEPORT"; do
    set -- $g
    svc="$(kc -n gateway get svc -o jsonpath='{range .items[*]}{.metadata.name} {.spec.ports[*].nodePort}{"\n"}{end}' 2>/dev/null | awk -v g="$1" -v p="$2" '$1 ~ g { for(i=2;i<=NF;i++) if($i==p) print $1 }')"
    if [[ -n "$svc" ]]; then vok "Gateway $1 的 Service $svc 在 NodePort $2"; else vbad "没找到 Gateway $1 在 NodePort $2 的 Service（docs/15 的待验证假设）"; fi
    port="$(v_http "http://$VLAN:$2/")"
    if [[ "$port" != 000 ]]; then vok "http://$VLAN:$2/ 有响应（$port；还没有路由时 404 是正常的）"; else vbad "http://$VLAN:$2/ 不通"; fi
  done
}

v_postgres() {
  v_need_cluster || return 0
  local r; r="$(kc -n cnpg-system get deploy cnpg-controller-manager -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  if [[ "${r:-0}" -ge 1 ]]; then vok "CloudNativePG 控制器在运行"; else vbad "CloudNativePG 控制器没在运行"; fi
  local ready phase inst prim
  ready="$(kc -n data get cluster pg-common -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  phase="$(kc -n data get cluster pg-common -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  inst="$(kc -n data get cluster pg-common -o jsonpath='{.status.readyInstances}/{.spec.instances}' 2>/dev/null || true)"
  if [[ "$ready" == True ]]; then vok "pg-common Ready（$phase，实例 $inst）"; else vbad "pg-common 没就绪：${phase:-没有这个集群}"; return 0; fi
  prim="$(kc -n data get cluster pg-common -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
  if [[ "$(kc -n data exec "$prim" -c postgres -- psql -U postgres -tAc 'select 1' 2>/dev/null)" == 1 ]]; then vok "主库 $prim 能查询"
  else vbad "主库 ${prim:-?} 执行 select 1 失败"; fi
  local sc; sc="$(kc -n data get pvc -l cnpg.io/cluster=pg-common -o jsonpath='{range .items[*]}{.spec.storageClassName}={.status.phase} {end}' 2>/dev/null || true)"
  if [[ "$sc" == *local-retain=Bound* ]]; then vok "数据卷：$sc"; else vbad "数据卷不是 local-retain 或没绑定：${sc:-读不到}"; fi
}

v_host_nginx() {
  local code; code="$(v_http "http://$VLAN/gateway-health")"
  if [[ "$code" == 200 ]]; then vok "http://$VLAN/gateway-health 200"; else vbad "http://$VLAN/gateway-health $(v_said "$code")"; fi
  v_need_host || return 0
  if systemctl is-active -q nginx 2>/dev/null; then vok "nginx 在运行"; else vbad "nginx 没在运行"; fi
  local own; own="$(ss -ltnpH 'sport = :80' 2>/dev/null | grep -o '"[^"]*"' | sort -u | tr '\n' ' ')"
  if [[ "$own" == '"nginx" ' ]]; then vok "80 端口只有 nginx"; else vbad "80 端口的主人：${own:-没有}"; fi
  if [[ -z "$(ss -ltnH 'sport = :443' 2>/dev/null)" ]]; then vok "443 没有监听（TLS 在边缘终结，docs/05）"; else vwarn "443 有监听"; fi
  if grep -qE '^\s*worker_connections\s+16384;' /etc/nginx/nginx.conf 2>/dev/null; then vok "worker_connections 16384"
  else vbad "worker_connections 不是 16384（1000 QPS 要用）"; fi
  local want; want="$(sed -e "s#@LAN_IP@#$VLAN#g" -e "s#@PUBLIC_PORT@#$GATEWAY_PUBLIC_NODEPORT#g" -e "s#@INTERNAL_PORT@#$GATEWAY_INTERNAL_NODEPORT#g" "$ROOT/infra/nginx/s2/ladder2.conf.tmpl")"
  if [[ "$want" == "$(cat /etc/nginx/conf.d/ladder2.conf 2>/dev/null)" ]]; then vok "/etc/nginx/conf.d/ladder2.conf 和模板一致"
  else vwarn "/etc/nginx/conf.d/ladder2.conf 和 infra/nginx/s2/ladder2.conf.tmpl 渲染出来的不同（服务器上被改过，或模板改了还没 prepare）"; fi
}

v_sample() {
  local host="sample.ladder2.internal" code
  if v_need_cluster; then
    local r; r="$(kc -n sample get deploy sample -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
    if [[ "${r:-0}" -ge 2 ]]; then vok "sample 有 $r 个副本可用"; else vbad "sample 可用副本 ${r:-0}，要 ≥ 2"; fi
    local p; p="$(kc -n sample get httproute sample -o jsonpath='{range .status.parents[*]}{.parentRef.name}={.conditions[?(@.type=="Accepted")].status} {end}' 2>/dev/null || true)"
    if [[ "$p" == *public=True* && "$p" == *internal=True* ]]; then vok "HTTPRoute 挂上了两个 Gateway：$p"; else vbad "HTTPRoute 状态：${p:-读不到}"; fi
    if v_on_host; then
      local cip; cip="$(kc -n sample get svc sample -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
      code="$(v_http "http://$cip/healthz")"
      if [[ "$code" == 200 ]]; then vok "service  http://$cip/healthz 200"; else vbad "service  http://$cip/healthz $(v_said "$code")"; fi
    else vunk "service 那一层（ClusterIP）要在 $VHOST 上才测得到"; fi
  fi
  code="$(v_http "http://$VLAN:$GATEWAY_PUBLIC_NODEPORT/healthz" "$host")"
  if [[ "$code" == 200 ]]; then vok "gateway public   :$GATEWAY_PUBLIC_NODEPORT 200"; else vbad "gateway public   :$GATEWAY_PUBLIC_NODEPORT $(v_said "$code")"; fi
  code="$(v_http "http://$VLAN:$GATEWAY_INTERNAL_NODEPORT/healthz" "$host")"
  if [[ "$code" == 200 ]]; then vok "gateway internal :$GATEWAY_INTERNAL_NODEPORT 200"; else vbad "gateway internal :$GATEWAY_INTERNAL_NODEPORT $(v_said "$code")"; fi
  code="$(v_http "http://$VLAN/healthz" "$host")"
  if [[ "$code" == 200 ]]; then vok "host-nginx       :80 200"; else vbad "host-nginx       :80 $(v_said "$code")"; fi
  # 网关认出的客户端地址（docs/05 的信任链）：host-nginx 写进 X-Forwarded-For 的第一个地址，
  # 应该就是网关认定的客户端。没认对时网关看到的是 flannel 网桥 cni0 的地址（Pod 网段里某个 /24 的 .1）。
  local who first gw
  who="$(curl -s --max-time 5 -H "Host: $host" "http://$VLAN/whoami" 2>/dev/null || true)"
  if [[ -z "$who" ]]; then vbad "http://$VLAN/whoami 没有响应"; return 0; fi
  first="$(awk -F'=' '$1=="x_forwarded_for"{split($2,a,", *"); print a[1]}' <<<"$who")"
  gw="$(awk -F'=' '$1=="x_real_ip"{print $2}' <<<"$who")"
  [[ -n "$gw" ]] || gw="$(awk -F'=' '$1=="x_forwarded_for"{n=split($2,a,", *"); if(n>1) print a[n]}' <<<"$who")"
  if [[ -z "$gw" || -z "$first" ]]; then vunk "网关没有传 X-Real-IP，也没有在 X-Forwarded-For 里追加地址，判断不了"
  elif [[ "$gw" == "$first" ]]; then vok "网关认出的客户端是 $gw，和 host-nginx 看到的一致（trustedAddresses 对）"
  else vbad "网关认出的客户端是 $gw，host-nginx 看到的是 $first：把 $gw 加进 ngf-values.yaml 的 trustedAddresses 再 prepare gateway"; fi
  vnote "$(tr '\n' ' ' <<<"$who")"
}

LT_DIR="${LADDER2_STATE_DIR:-$HOME/.local/state/de-ladder2}/loadtest"
LT_RESULTS="$LT_DIR/results.tsv"
LT_REQUIRED=("sample service" "sample gateway" "sample-internal gateway" "sample host-nginx" "pg-common pg")

v_loadtest() {
  if [[ ! -s "$LT_RESULTS" ]]; then
    vunk "这台机器上没有压测记录（$LT_RESULTS）。记录在跑 loadtest 的那台机器上"
    return 0
  fi
  local rh line
  for rh in "${LT_REQUIRED[@]}"; do
    set -- $rh
    line="$(awk -F'\t' -v r="$1" -v h="$2" '$2==r && $3==h' "$LT_RESULTS" | tail -1)"
    if [[ -z "$line" ]]; then vbad "$1 / $2 还没压过"; continue; fi
    # 列：时间 链路 层 从哪 目标速率 实际速率 p50 p95 p99 错误率 丢弃 结果 编号
    if awk -F'\t' '{exit !($12=="通过" && $5+0>=1000)}' <<<"$line"; then
      vok "$(awk -F'\t' '{printf "%s / %s：%s/s，p95 %s ms，p99 %s ms，错误 %s（%s）", $2, $3, $6, $8, $9, $10, $1}' <<<"$line")"
    else
      vbad "$(awk -F'\t' '{printf "%s / %s：目标 %s/s，实际 %s/s，p95 %s，p99 %s，错误 %s，%s（%s）", $2, $3, $5, $6, $8, $9, $10, $12, $1}' <<<"$line")"
    fi
  done
}

v_edge() {
  local edge; edge="$(probe_field sample edge)"
  if [[ -z "$edge" || "$edge" == *待确认* ]]; then
    vbad "sample 的 edge 还没登记：Domestic 还没接到 s2（手工，docs/35）"
  else
    local code; code="$(v_http "$edge/healthz")"
    if [[ "$code" == 200 ]]; then vok "$edge/healthz 200"; else vbad "$edge/healthz $(v_said "$code")"; fi
  fi
  if v_on_host; then
    if [[ $EUID -eq 0 ]] && command -v wg >/dev/null; then
      local hs; hs="$(wg show all latest-handshakes 2>/dev/null || true)"
      if [[ -n "$hs" ]]; then vok "WireGuard 有对端：$(awk '{printf "%s ", $1}' <<<"$hs")（probe wg 看握手时间）"; else vbad "这台没有 WireGuard 对端"; fi
    else vunk "WireGuard 状态要 root 和 wg 命令才读得到"; fi
  fi
}

stage_verify() {
  local h="$1"; shift
  local only="" a
  VCTX=ladder2
  while (( $# )); do
    case "$1" in
      --context) VCTX="${2:-}"; shift 2 || true ;;
      --context=*) VCTX="${1#*=}"; shift ;;
      -*) die "未知参数：$1" ;;
      *) only="$1"; shift ;;
    esac
  done
  [[ -z "$only" ]] || stage_desc "$only" >/dev/null || die "没有阶段 $only。阶段：${STAGES[*]}"
  VHOST="$h"; VLAN="$(host_field "$h" lan_ip)"
  if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "$VCTX"; then VCLUSTER="kubeconfig 里没有 context $VCTX"
  elif ! kubectl --context "$VCTX" --request-timeout=8s get --raw /readyz >/dev/null 2>&1; then VCLUSTER="API 不通"
  else VCLUSTER=yes; fi
  echo "${B}$h${O}  地址 $VLAN（来自 $(site_lan_source "$h")）；集群 context $VCTX（$([[ "$VCLUSTER" == yes ]] && echo 连得上 || echo "$VCLUSTER")）；本机$(v_on_host && echo "就是 $h" || echo "不是 $h")"
  if ! v_on_host; then
    # 机器其实就是这台、只是登记的地址不对时，这一行能直接看出来（docs/15 第 76 项）
    echo "  本机 $(hostname -s 2>/dev/null) 的地址：$(local_ips | grep -vE '^(127\.|169\.254\.)' | sort -u | tr '\n' ' ')。如果这台就是 $h：这次用 $(site_env_name "$h" lan_ip)=<地址>（写在命令前或 .env），长期变了改 inventory/hosts.yaml，不要改机器（docs/50）"
  fi
  local s summary=() b u o
  for s in "${STAGES[@]}"; do
    [[ -z "$only" || "$only" == "$s" ]] || continue
    echo "${B}$s${O}  ${D}$(stage_desc "$s")${O}"
    b=$V_BAD; u=$V_UNK; o=$V_OK
    "v_${s//-/_}"
    b=$((V_BAD-b)); u=$((V_UNK-u)); o=$((V_OK-o))
    if (( b )); then summary+=("$(printf "  %-11s ${R}✗ %d 项没过${O}%s" "$s" "$b" "$( (( u )) && echo "，$u 项 UNKNOWN")")")
    elif (( u )); then summary+=("$(printf "  %-11s ${Y}UNKNOWN %d 项${O}" "$s" "$u")")
    else summary+=("$(printf "  %-11s ${G}✓ 完成${O}（%d 项）" "$s" "$o")"); fi
  done
  if [[ -z "$only" ]]; then
    echo; echo "${B}汇总${O}"; printf '%s\n' "${summary[@]}"
  fi
  echo "${D}只读：没有改任何东西。UNKNOWN 表示从这里查不到（不在 $h 上，或连不上集群），不等于没做。${O}"
  (( V_BAD == 0 && V_UNK == 0 )) || exit 1
}
