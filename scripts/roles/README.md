# 角色脚本

日期：2026-11-17。状态：只有约定，脚本还没写。

每个角色（`control`、`node`、`site`、`edge`，见 `docs/17`）一个目录，里面的脚本按编号顺序执行，每个都可以重复执行。`manage.sh node prepare|join` 通过 SSH 把它们送到目标机器上运行。

```text
roles/
├── common/        # 所有角色：主机名、时间同步、内核参数、磁盘、NAS 挂载、隧道
├── control/       # kubeadm init、flannel、本地卷、平台组件、备份定时任务
├── node/          # 容器运行时、kubeadm join、GPU 驱动和标签
├── site/          # Docker、Compose、站点的 Nginx 和同步任务
└── edge/          # Nginx、证书、WireGuard 中继
```

规矩：脚本不写死包管理器（s1 是 CentOS 系，s2 是 Ubuntu）；不含任何地址和凭据，这些从 `inventory/` 和目标机器上的文件读；每个脚本先检查再动手，已经是目标状态就什么都不做。
