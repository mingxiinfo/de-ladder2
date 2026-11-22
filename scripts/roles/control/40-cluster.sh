#!/usr/bin/env bash
# 阶段 cluster：kubeadm init 建新集群 ladder2；单节点去掉控制面污点；kubeconfig 的 context 命名为 ladder2（docs/14 修订、docs/16、docs/35）。
# 已经建过（/etc/kubernetes/admin.conf 存在）就不再 init。不提供 kubeadm reset。
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_root
guard_target

command -v kubeadm >/dev/null || die "没有 kubeadm。先做阶段 runtime。"
# NAS 暂缓时（用户 2026-11-22，docs/51）可以先建集群：只有阶段 nas 做过（kubelet 已经配成等 NAS）才要求 NAS 挂着
if [[ -f /etc/systemd/system/kubelet.service.d/10-requires-nas.conf ]]; then
  mountpoint -q /mnt/nas || die "/mnt/nas 没有挂载，而阶段 nas 已经让 kubelet 等 NAS。先把 NAS 挂上。"
else
  note "NAS 暂缓（docs/51）：kubelet 不等 NAS。以后做阶段 nas 会补上这个依赖，再做阶段 backup"
fi
[[ "$(swapon --show --noheadings | wc -l)" -eq 0 ]] || die "swap 没关。先做阶段 host。"

ADMIN=/etc/kubernetes/admin.conf
if [[ -f "$ADMIN" ]]; then
  say "集群已经建过（$ADMIN 存在），不再 init"
else
  say "渲染 kubeadm 配置"
  ver="$(kubeadm version -o short)"
  wg="$(host_field "$HOST" wg_ip)"
  cfg=/root/ladder2-kubeadm-init.yaml
  sed -e "s#@NODE_NAME@#$(hostname -s)#g" \
      -e "s#@K8S_VERSION@#$ver#g" \
      -e "s#@LAN_IP@#$LAN_IP#g" \
      -e "s#@IMAGE_REPOSITORY@#$K8S_IMAGE_REPOSITORY#g" \
      "$ROOT/infra/k8s/cluster/kubeadm-init.yaml" >"$cfg.tmp"
  if is_ip "$wg"; then sed -i "s#@WG_IP@#$wg#g" "$cfg.tmp"
  else sed -i '/@WG_IP@/d' "$cfg.tmp"; note "wg_ip 没登记（$wg），证书里先不放 WireGuard 地址。以后要加得重签 apiserver 证书"; fi
  ! grep -q '@[A-Z0-9_]*@' "$cfg.tmp" || die "渲染后还有没替换的占位：$(grep -o '@[A-Z0-9_]*@' "$cfg.tmp" | sort -u | tr '\n' ' ')"
  mv "$cfg.tmp" "$cfg"; chmod 600 "$cfg"
  done_ "$cfg"

  say "拉控制面镜像（$K8S_IMAGE_REPOSITORY）"
  kubeadm config images pull --config "$cfg"

  say "kubeadm init"
  kubeadm init --config "$cfg" --upload-certs
fi

say "kubeconfig：context 叫 ladder2（CLAUDE.md：会修改集群的命令都带 --context，不用默认的）"
install -d -m 0700 /root/.kube
tmp="$(mktemp)"
KUBECONFIG="$ADMIN" kubectl config view --raw >"$tmp"
old_ctx="$(KUBECONFIG="$tmp" kubectl config current-context)"
[[ "$old_ctx" == ladder2 ]] || KUBECONFIG="$tmp" kubectl config rename-context "$old_ctx" ladder2 >/dev/null
write_file /root/.kube/ladder2.conf 0600 <"$tmp"
rm -f "$tmp"
if [[ ! -f /root/.kube/config ]]; then
  cp /root/.kube/ladder2.conf /root/.kube/config; chmod 600 /root/.kube/config
  echo "  ✎ /root/.kube/config"
elif ! KUBECONFIG=/root/.kube/config kubectl config get-contexts -o name | grep -qx ladder2; then
  backup_once /root/.kube/config
  KUBECONFIG=/root/.kube/config:/root/.kube/ladder2.conf kubectl config view --raw --flatten >/root/.kube/config.new
  mv /root/.kube/config.new /root/.kube/config; chmod 600 /root/.kube/config
  echo "  ✎ /root/.kube/config：合并了 context ladder2"
fi
k() { kubectl --context ladder2 --request-timeout=20s "$@"; }

say "单节点：去掉控制面的污点，业务才能调度上来"
if k get node -o jsonpath='{.items[*].spec.taints[*].key}' | grep -qw node-role.kubernetes.io/control-plane; then
  k taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null
  echo "  ✎ 已去掉"
else
  note "已经没有"
fi

say "节点标签：这台持有 Launcher 的 service peer（docs/47）"
# Launcher 建的 host-runner DaemonSet 只在打了这个标签的节点上跑（MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR）
node_name="$(k get node -o jsonpath='{.items[0].metadata.name}')"
if [[ "$(k get node "$node_name" -o jsonpath='{.metadata.labels.mx\.ladder2/site-peer}')" == true ]]; then
  note "$node_name 已经有 mx.ladder2/site-peer=true"
else
  k label node "$node_name" mx.ladder2/site-peer=true --overwrite >/dev/null
  echo "  ✎ $node_name mx.ladder2/site-peer=true"
fi

say "API"
k get --raw /readyz >/dev/null && done_ "API 就绪"
note "节点在装 flannel 之前是 NotReady，这是正常的。下一步：node prepare $HOST network --context ladder2"
note "运维机要用这个集群：把 /root/.kube/ladder2.conf 拷过去合并，并在运维机的 /etc/hosts 加一行 $LAN_IP k8s-api.ladder2.internal"
