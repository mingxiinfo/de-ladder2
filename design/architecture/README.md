# design/architecture：当前整体设计的架构图

日期：2026-11-17。状态：六张图都通过了 Archify 的 showcase 校验，都截图看过。画的是设计，不是现状：没有一样在服务器上部署过。内容以 `docs/16`–`34` 为准。站点和镜像见 `docs/31`。

| 文件 | 内容 | 在时间线的哪个阶段 |
|---|---|---|
| `01-overview` | 全景：外部和内部流量路径、宿主机 / Docker / Kubernetes 各放什么、s1 和 s2、NAS、OSS、Oversea | 阶段 A |
| `02-onboarding` | 接入方式：自己的服务、业务项目、Compose、宿主机进程怎么接到 host-nginx 和 Gateway | 阶段 A |
| `03-evolution` | 全部阶段一张图 | 阶段 C |
| `04-stage-b` | s1 重装并入，一个集群两台 | 阶段 B |
| `05-stage-c` | 三台控制面，向外加入口和站点 | 阶段 C |
| `06-toc-oversea` | toC 站点：arguseek 和 Delta 在一台云服务器上，区域待定；跨境的只有查 Hub 和 NAS 读写（`docs/33`、`docs/34`） | 参考图，不属于某个阶段：站点不进集群，和 s2 无关，现在就能做 |
| `07-edge` | 边缘机器：Internal（s2）上的 `qp-tunnel-cli edge` 经 SSH 和跳板机推送；机器上先 preflight 再切 `current`；三种技术栈、两个系统族；v1 Launcher 推的不接管（`docs/37`、`docs/38`） | 参考图，不属于某个阶段：边缘机器不进集群。2026-11-21 加，Archify 校验通过，截图看过 |

改图：编辑同名的 `.architecture.json`，或者改 `gen.py` 后在仓库根目录运行 `python3 design/architecture/gen.py`（它会重写全部七个源文件）。然后：

```bash
./scripts/manage.sh diagrams 04-stage-b
```

写图的经验在 `docs/13`。另外：一张图的总宽度有上限，七列放不下，六列可以；卡片圆点颜色只能用 cyan、emerald、violet、amber、rose、orange、slate；组件的名字太长会报溢出，缩短或拆到副标题里。
