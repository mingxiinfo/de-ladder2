#!/usr/bin/env bash
# 阶段 backup：建完集群先装备份，再部署任何业务（docs/14 第 9 节、docs/19、docs/35）。
# 现在只有 etcd 快照和 pki。数据库的备份等 pg-common 有了数据再加（manage.sh backup run 还没实现）。
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
need_root
guard_target
[[ -f /etc/kubernetes/admin.conf ]] || die "还没有集群。先做阶段 cluster。"

say "备份脚本"
write_file /usr/local/sbin/ladder2-etcd-backup 0755 <"$ROLES_DIR/control/files/ladder2-etcd-backup.sh"

say "systemd 定时器：每天 02:00（docs/19）"
write_file /etc/systemd/system/ladder2-etcd-backup.service <<'EOF'
# de-ladder2（docs/35）
[Unit]
Description=ladder2 etcd 快照和 pki 写到 NAS
RequiresMountsFor=/mnt/nas
After=kubelet.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ladder2-etcd-backup
EOF
write_file /etc/systemd/system/ladder2-etcd-backup.timer <<'EOF'
# de-ladder2（docs/35）
[Unit]
Description=每天 02:00 备份 ladder2 的 etcd

[Timer]
OnCalendar=*-*-* 02:00:00
# 关机错过了，开机后补一次
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now ladder2-etcd-backup.timer >/dev/null 2>&1
done_ "定时器已启用：$(systemctl show -p NextElapseUSecRealtime --value ladder2-etcd-backup.timer 2>/dev/null || echo 未知)"

say "现在先跑一次，确认能写到 NAS"
if systemctl start ladder2-etcd-backup.service; then
  journalctl -u ladder2-etcd-backup.service -n 3 --no-pager | tail -1
else
  journalctl -u ladder2-etcd-backup.service -n 20 --no-pager
  die "第一次备份失败，上面是日志"
fi
