# 角色脚本

日期：2026-11-17。状态：2026-11-19 写了 `common/`（host、nas）和 `control/`（runtime、cluster、backup、host-nginx），由 `node prepare <主机> <阶段>` 在目标机器本机以 root 运行（`docs/35`），没在 s2 上跑过。`node/`、`site/`、`edge/` 还没写；通过 SSH 远程执行也还没有。

每个角色（`control`、`node`、`site`、`edge`，见 `docs/17`）一个目录，里面的脚本按编号顺序执行，每个都可以重复执行。`manage.sh node prepare|join` 通过 SSH 把它们送到目标机器上运行。

```text
roles/
├── lib.sh         # 公共函数：读 inventory、写文件前留备份、PROXY、不在 s1 上运行的防护
├── common/        # 10-host.sh 系统参数；20-nas.sh 挂 NAS
├── control/       # 30-runtime.sh、40-cluster.sh、50-backup.sh、60-host-nginx.sh；files/ 是装到机器上的脚本
├── node/          # 容器运行时、kubeadm join、GPU 驱动和标签
├── site/          # Docker、Compose、站点的 Nginx 和同步任务
└── edge/          # Nginx、证书、WireGuard 中继
```

规矩：脚本不写死包管理器（s1 是 CentOS 系，s2 是 Ubuntu）；不含任何地址和凭据，这些从 `inventory/` 和目标机器上的文件读；每个脚本先检查再动手，已经是目标状态就什么都不做。
