#!/usr/bin/env bash
# 阶段 nas：按 inventory/hosts.yaml 的 nas.fstab 挂 NAS，并让 kubelet 在 NAS 挂好之后再启动（docs/14、docs/35）。
# 只加挂载，不改 NAS 上任何东西。
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_root
guard_target

line="$(host_block nas fstab)"
[[ -n "$line" ]] || die "inventory/hosts.yaml 的 nas.fstab 是空的"
mnt="$(awk '{print $2}' <<<"$line")"
[[ "$mnt" == /mnt/nas ]] || die "nas.fstab 的挂载点不是 /mnt/nas：$mnt"

say "NFS 客户端"
if ! command -v mount.nfs >/dev/null; then need_apt; apt_get install nfs-common; fi
done_ "mount.nfs"

say "fstab"
if awk -v m="$mnt" '$1 !~ /^#/ && $2==m {f=1} END{exit !f}' /etc/fstab; then
  note "已有 $mnt 的一行，不改（和登记的不同时，node verify 会提示）"
else
  backup_once /etc/fstab
  echo "$line" >>/etc/fstab
  echo "  ✎ /etc/fstab"
  systemctl daemon-reload
fi

say "挂载"
mkdir -p "$mnt"
if mountpoint -q "$mnt"; then
  note "已挂载"
else
  if ! timeout 70 mount "$mnt"; then
    die "挂不上 $mnt。最常见的原因是 NAS 的 NFS 权限只放行了 s1 的地址，要在 NAS 管理界面给 $LAN_IP 加读写权限（docs/35）。"
  fi
fi
timeout 10 ls "$mnt" >/dev/null || die "$mnt 挂上了但 10 秒内读不出"
done_ "$mnt 可读：$(timeout 10 ls "$mnt" | head -5 | tr '\n' ' ')"

say "kubelet 等 NAS 挂好再启动"
write_file /etc/systemd/system/kubelet.service.d/10-requires-nas.conf <<'EOF'
# de-ladder2（docs/14、docs/35）。NAS 没挂上时 kubelet 不启动，避免 Pod 把数据写进空的挂载点目录。
[Unit]
RequiresMountsFor=/mnt/nas
EOF
systemctl daemon-reload
