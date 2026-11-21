#!/usr/bin/env bash
# 新集群 ladder2 的 etcd 快照和 /etc/kubernetes/pki，每天写到 NAS（docs/19、docs/35）。
# 由 scripts/roles/control/50-backup.sh 装到 /usr/local/sbin/ladder2-etcd-backup，systemd 定时器每天 02:00 运行。
# 只写新目录，不清理旧的（保留份数以后由 manage.sh backup 管，docs/19）。
# 目录结构是 docs/19 备份包的一部分：ladder2-backup-<时间>/cluster/{etcd-snapshot.db,pki.tar}。
set -euo pipefail

DEST_ROOT="${LADDER2_BACKUP_DIR:-/mnt/nas/backup}"
export KUBECONFIG=/etc/kubernetes/admin.conf

mountpoint -q /mnt/nas || { echo "错误：/mnt/nas 没有挂载，不备份" >&2; exit 1; }
ts="$(date +%Y%m%d-%H%M%S)"
pkg="$DEST_ROOT/ladder2-backup-$ts"
mkdir -p "$pkg/cluster"
chmod 700 "$pkg" || true   # NAS 用 root squash 时可能改不了权限，不因此失败

pod="$(kubectl -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$pod" ]] || { echo "错误：找不到 etcd 的 Pod" >&2; exit 1; }
# 快照先写在 etcd 自己的数据目录（宿主机同一路径，hostPath 挂进 Pod），再搬到 NAS。
tmp=/var/lib/etcd/ladder2-snapshot.db
certs=(--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt --key=/etc/kubernetes/pki/etcd/healthcheck-client.key)
kubectl -n kube-system exec "$pod" -- etcdctl --endpoints=https://127.0.0.1:2379 "${certs[@]}" snapshot save "$tmp" >/dev/null
# 快照的校验信息（哈希、版本、键数）。镜像里没有 etcdutl 时记 null，不因此失败。
status="$(kubectl -n kube-system exec "$pod" -- etcdutl snapshot status "$tmp" -w json 2>/dev/null || echo null)"
[[ -n "$status" ]] || status=null
mv "$tmp" "$pkg/cluster/etcd-snapshot.db"
tar -C /etc/kubernetes -cf "$pkg/cluster/pki.tar" pki
( cd "$pkg/cluster" && sha256sum etcd-snapshot.db pki.tar >SHA256SUMS )
cat >"$pkg/MANIFEST.json" <<EOF
{
  "created_at": "$(date -Iseconds)",
  "host": "$(hostname -s)",
  "partial": true,
  "items": ["cluster-etcd", "cluster-pki"],
  "etcd_snapshot_status": $status,
  "note": "只有集群状态。数据库等其余备份项由 manage.sh backup run 写（docs/19，还没实现）。pki.tar 含 CA 私钥，没有加密（docs/15 第 17 项）。"
}
EOF
echo "ladder2 etcd 备份完成：$pkg（$(du -sh "$pkg" | cut -f1)）"
