#!/usr/bin/env bash
# 阶段 host：系统参数。可以重复执行，已经是目标状态就不动（docs/35）。
# 不改主机名：主机名由人定（inventory/hosts.yaml 的 name），这里只检查。
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_root
guard_target

say "主机名"
hn="$(hostname -s)"
[[ "$hn" != localhost* && -n "$hn" ]] || die "先设主机名（建议 $(host_field "$HOST" name)）：hostnamectl set-hostname <名字>"
done_ "$hn"

say "/etc/hosts：API 的固定名字 k8s-api.ladder2.internal 指向 $LAN_IP（docs/16）"
if awk -v ip="$LAN_IP" '$1==ip { for(i=2;i<=NF;i++) if($i=="k8s-api.ladder2.internal") f=1 } END{exit !f}' /etc/hosts; then
  note "已有"
elif grep -qw 'k8s-api.ladder2.internal' /etc/hosts; then
  die "/etc/hosts 里 k8s-api.ladder2.internal 指向了别的地址。先人工核对。"
else
  backup_once /etc/hosts
  echo "$LAN_IP k8s-api.ladder2.internal" >>/etc/hosts
  echo "  ✎ /etc/hosts"
fi
nas_ip="$(host_field nas lan_ip)"
if is_ip "$nas_ip" && ! getent hosts nas-storage >/dev/null; then
  backup_once /etc/hosts
  echo "$nas_ip nas-storage" >>/etc/hosts
  echo "  ✎ /etc/hosts：nas-storage → $nas_ip（与 s1 的 fstab 写法一致）"
fi

say "关闭 swap（kubelet 默认要求）"
swapoff -a
if grep -Eq '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab; then
  backup_once /etc/fstab
  sed -i '/^[^#].*[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab
  echo "  ✎ /etc/fstab：注释掉 swap 行"
fi
done_ "swap 已关"

say "内核模块"
write_file /etc/modules-load.d/ladder2-k8s.conf <<'EOF'
# de-ladder2（docs/35）。容器网络和连接跟踪需要。
overlay
br_netfilter
nf_conntrack
EOF
modprobe overlay; modprobe br_netfilter; modprobe nf_conntrack

say "内核参数"
write_file /etc/sysctl.d/90-ladder2.conf <<'EOF'
# de-ladder2（docs/35）。改这里要同时改 scripts/roles/common/10-host.sh 和 node verify 的检查。
# Kubernetes（docs/14）
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
# Elasticsearch（docs/14）
vm.max_map_count = 262144
# 1000 QPS（docs/21、docs/35）：连接跟踪表、监听队列、文件句柄、文件监视
# 本地端口范围不改：默认 32768–60999，正好避开 NodePort 的 30000–32767。
net.netfilter.nf_conntrack_max = 1048576
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 1048576
EOF
sysctl --system >/dev/null
done_ "已生效"

say "时间同步（etcd 和证书依赖时间）"
if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == yes ]]; then
  done_ "已同步"
else
  timedatectl set-ntp true || true
  note "已打开 NTP。同步要几分钟，之后 node verify $HOST host 再看"
fi

say "防火墙（只查不改）"
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  note "ufw 在运行。要放行的端口和来源见 docs/35 的“防火墙”一节，由人执行。"
else
  note "ufw 没有运行"
fi
