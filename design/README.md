# design：架构图，和查看它们的站点

日期：2026-11-17。状态：开发机上构建和运行通过（两种网络模式、默认的 0.0.0.0 都试过）；s1 上 `design build` 通过，修改后的 `design up` 还没在 s1 上跑过。

| 目录 | 是什么 | 属于架构吗 |
|---|---|---|
| `architecture/` | 当前设计的五张架构图（Archify 源和生成的 HTML） | 是。改设计时要同步改 |
| `site/` | 查看站点的首页和演变时间线 `timeline.json` | 否，是工具（`docs/32`） |
| `deploy/` | 站点的 Dockerfile、容器里的 Nginx 模板、compose、`design.env` | 否，是工具 |

## 查看站点

把架构图和演变时间线放在一个网页里看。它只是看设计用的工具，不登记到 `inventory/`，不接 host-nginx 和 Gateway，放在哪台机器都行。构建和运行的细节在 `docs/31`。

```bash
./scripts/manage.sh design serve     # 不用 Docker，本机预览 http://127.0.0.1:8310/
./scripts/manage.sh design build     # 打镜像；内网服务器加 PROXY=http://127.0.0.1:7788
./scripts/manage.sh design up        # 启动，默认听 0.0.0.0:18310，其他机器直接打开 http://<这台机器>:18310/
./scripts/manage.sh design status
./scripts/manage.sh design stop
```

监听地址在 `deploy/design.env` 的 `DESIGN_BIND`，默认 `0.0.0.0`，也可以临时用环境变量覆盖：

| 设置 | 谁能打开 |
|---|---|
| `0.0.0.0`（默认） | 能到这台机器任一网卡的人，包括经 WireGuard、OpenVPN 隧道来的 |
| 这台机器的 LAN 地址 | 只有办公网 |
| `127.0.0.1` | 只有本机。别处看用 `ssh -L 18310:127.0.0.1:18310 root@<服务器>`，再打开 http://127.0.0.1:18310/ |

端口在听，其他机器仍打不开时，多半是防火墙。`design up` 会查 firewalld 或 ufw 有没有放行 18310，没有就提示放行命令，**但不替你执行**：放行是 iptables 的改动。

- 不新建 Docker 网络：Linux 上用 host 网络，Mac 上用 Docker 自带的默认 bridge。s1 上新建网络会失败（`docs/31`）。
- 端口、监听地址、基础镜像版本在 `deploy/design.env`。

## 改了架构之后

1. 新增一篇 `docs/NN`。
2. 改 `architecture/` 里的图：编辑 `.architecture.json`，或改 `gen.py` 后运行，再 `./scripts/manage.sh diagrams`。
3. 改 `site/timeline.json` 里的阶段说明和轮次记录。
4. 想在站点里看到，`design build`、`design up`。
