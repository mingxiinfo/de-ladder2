# 文档索引

编号递增。新决策新增一篇，不改写旧的；旧文档过时了，在它的状态行里写"已被 NN 取代"。

每篇第一段是日期和状态。状态要说清楚这是设计、计划，还是在哪台机器上实测过。

| 编号 | 文档 | 回答什么 |
|---|---|---|
| 01 | [背景、现状与目标](01.background-and-goals.md) | 现在有什么、哪些不能碰、要达到什么 |
| 02 | [仓库策略](02.repo-strategy.md) | 原地升级还是拷贝；别人的项目放哪 |
| 03 | [目标架构总览](03.target-architecture.md) | 分几层、每层谁管、用什么组件 |
| 04 | [集群拓扑与扩展](04.cluster-and-scaling.md) | 两台、三台、更多；高可用还是扩容；单机到上限怎么办 |
| 05 | [入口与网关](05.gateway-and-ingress.md) | Nginx、Caddy、Gateway API 各在哪一层 |
| 06 | [数据库](06.database-ha-dr.md) | 高可用、灾备、读写分离 |
| 07 | [存储、NAS 与静态文件](07.storage-nas-static.md) | 数据放哪块盘；mx-static 怎么上线；缓存 |
| 08 | [网络与云服务器](08.network-and-cloud.md) | 隧道、地址规划、云服务器怎么接 |
| 09 | [容量：1000 QPS](09.capacity-1000qps.md) | 每个环节的预算和瓶颈 |
| 10 | [项目接入](10.project-onboarding.md) | 别人的项目怎么进集群或直接部署 |
| 11 | [迁移路线与验收](11.migration-roadmap.md) | 先迁什么后迁什么；怎么保护 MX-H2I |
| 12 | [运维入口](12.ops-and-manage.md) | manage.sh 的命令和规矩 |
| 13 | [架构图](13.diagrams.md) | 图怎么画、图册怎么生成 |
| 14 | [从 0 到 1](14.bootstrap-from-zero.md) | 一台新服务器怎么变成集群节点 |
| 15 | [待确认事项](15.open-questions.md) | 还不知道的、还没决定的、还没验证的 |
| 16 | [第二轮决策](16.decisions-round2-kubeadm-no-witness.md) | 为什么用 kubeadm、不设见证机、s1 暂不调整 |
| 17 | [节点、站点与多入口](17.nodes-sites-and-entry-scaling.md) | 新机器怎么接入；云和海外站点；入口带宽；面向公众的站点 |
| 18 | [内网专属入口](18.internal-only-entry.md) | Caddy、分流 DNS / NRPT；两个 Gateway |
| 19 | [备份与一键还原](19.backup-and-restore.md) | 备份什么、放哪、怎么用 manage.sh 全部还原 |
| 20 | [磁盘增长与数据放置](20.disk-growth-and-data-placement.md) | s1 磁盘现状；宿主机 PG 搬哪；业务怎么读 NAS；GPU；平台与业务的边界 |
| 21 | [第三轮决策](21.decisions-round3-naming-and-scope.md) | s1 最后怎么并入；命名；Launcher 和 L2 各管什么；GPU；项目目录；etcd 和 flannel 会不会是瓶颈 |
| 22 | [数据库容灾分级与备份占用](22.database-dr-tiers-and-backup-sizing.md) | 另一台会不会一样大；副本、备份、归档的区别；备份放哪 |
| 23 | [两层 Nginx](23.entry-layers-host-nginx-and-gateway.md) | host-nginx 和集群里的 Gateway 各管什么；集群重启时会怎样 |
| 24 | [隧道与 Oversea 访问](24.tunnels-wireguard-hysteria2-and-oversea-access.md) | WireGuard 会不会断；Hysteria2 快不快；Oversea 怎么用 NAS 和内网服务 |
| 25 | [NAS 文件访问与云 NAS](25.nas-file-access-and-cloud-nas.md) | 静态文件走哪条路；mx-static 的位置；云上的 NAS 是什么 |
| 26 | [管理面与探测](26.management-plane-and-probes.md) | 引进哪些现成工具；主控坏了会怎样；一键测各段耗时；控制台怎么组织 |
| 27 | [第四轮决策](27.decisions-round4-egress-dirs-db-instances.md) | 经 Domestic 出网；大文件走不走代理；`services/` 和 `projects/`；数据库实例怎么分 |
| 28 | [监控、Launcher 的角色与自动化](28.monitoring-launcher-role-and-automation.md) | Prometheus 这一套重不重；Launcher 该不该当控制面；自动化和测试放哪 |
| 29 | [交接](29.handoff-and-next-steps.md) | 现在到哪了；下次从哪继续 |
| 30 | [运维面、带宽、架构图](30.ops-plane-jenkins-uplink-and-architecture-diagrams.md) | Jenkins 归到运维面 `mx-ops`；内网 300 Mbps 意味着什么；`design/architecture/` 的三张图 |
| 31 | [架构图站点](31.design-site-docker.md) | `design/` 打成 Docker 镜像；演变时间线；怎么更新；图上的措辞 |

**接着做：先读 29，再读 30、31。** 第一次读：01 → 16 → 21 → 27 → 03 → 17 → 11。要动手：14 → 19 → 22 → 12。

03–14 是第一轮设计，16–20 是第二轮，21–26 是第三轮，27–28 是第四轮。被后面取代的部分在各自的状态行里标明了。两处说法不一致时以编号大的为准。

## 相关工程的文档

本工程不重复它们的内容，只引用。

| 内容 | 位置 |
|---|---|
| Launcher 的历史设计和最新理念（00–63） | `de-llaaddddeerr/electron-dock/mx-launcher/docs/` |
| L1 的统一部署入口和开机恢复 | `de-llaaddddeerr/electron-dock/README.md` |
| L1 的部署契约和换机恢复设计 | `mx-launcher/docs/34-platform-deploy-and-recovery-contract.md` |
| 80 端口归属事故 | `mx-launcher/docs/50-internal-gateway-port80-ownership.md` |
| 存储和部署事故 | `mx-launcher/docs/51-internal-server-storage-deploy-incident-2026-10-19.md` |
| Domestic 容量分析 | `mx-launcher/docs/53-luopan-login-and-domestic-capacity-review-2026-10-22.md` |
| etcd 和 k8s 数据迁移 | `electron-dock/mx-base/mx-move/README.md` |
| mx-static 和 NAS 迁移 | `electron-dock/mx-base/mx-static/docs/`、`nas_docs/` |
| Hub 技术图册（Archify 样例） | `electron-dock/mx-insight-hub/docs/architecture/atlas/` |
| OpenVPN mesh | `de-llaaddddeerr/electron-plugin/packages/tunnel-cli/openvpn.setup.md` |
| 网关选型和两台服务器容灾（本工程 03–06 的前身） | `cc-studio/docs/03.k8s-gateway-and-dr.md` |
| Domestic 和 Internal 的 Nginx 配置 | `mingxi/de-mingxi/compass/deploy/` |
| Night-All 的实现和规划 | `mingxi/Night-All/docs/`、`specs/` |
