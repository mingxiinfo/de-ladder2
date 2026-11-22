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
| 31 | [查看站点（工具）](31.design-site-docker.md) | `design/` 打成 Docker 镜像；演变时间线；怎么更新；图上的措辞 |
| 32 | [查看站点不属于架构](32.design-site-is-a-tool.md) | 站点只是看文档和图的工具：不登记、不接入口、不画进架构图 |
| 33 | [toC 海外站点](33.toc-oversea-site-arguseek-and-delta.md) | arguseek 和 Delta 放在海外云服务器上：放什么、怎么调 Hub、NAS 数据怎么过去、备份 |
| 34 | [toC 站点的区域和 NAS 读写](34.toc-site-region-and-nas-read-write.md) | 区域怎么选、怎么测；站点怎么读写 NAS：rclone 本机缓存加内网发起的隧道 |
| 35 | [s2 落地的阶段和 1000 QPS](35.s2-bring-up-stages-and-1000qps.md) | s2 分哪 14 个阶段、每个阶段用哪条命令做和验；每一层怎么压 1000 QPS、门槛是多少 |
| 36 | [Launcher 先上 L2，ladder1 副本](36.launcher-first-on-l2-and-ladder1-copy.md) | 为什么把 L1 拷到 `ladder1/`；Launcher 控制面在 L2 上怎么重新设计；s2 上先复刻、切换最后；一台还是两台 master |
| 37 | [多台 Domestic 和 edge 推送工具](37.multi-domestic-entry-and-edge-push-tool.md) | 第二台 Domestic 怎么分担和容灾；CPU 96% 先看什么；`qp-tunnel-cli edge` 怎么从 Internal 推送部署到边缘；ladder1 移出 Git |
| 38 | [edge 的技术栈、状态视图和系统族](38.edge-stacks-status-and-os-families.md) | `resources/edge/stacks` 按技术栈分：wg-nginx、open-nginx、hy2-mihomo；Hysteria2 服务端怎么推；`edge status` 看本机和每台机器上有什么；Ubuntu 和 CentOS 怎么分开处理；"双 master"为什么仍不做 |
| 39 | [多台推送机、关系列表和配置目录](39.multiple-push-origins-relations-and-state-home.md) | "双 master"是两台推送机；机器记着谁管哪个组件，换推送机要 `--take-over`；`edge relations`；配置目录放推送机的 `/var/lib/qp-tunnel/edge`，`state pull` 拿回；有 v1 组件的机器整台不推；hy2 镜像固定；s1 是 CentOS Linux 8 且不换 |
| 40 | [domestic02 到 internal02 的隧道](40.edge-link-domestic02-internal02.md) | 照 L1 的 `mx-domestic` 10.88.0.1 / `mx-internal-svc` 10.88.88.88 做：`edge link init` 在 internal02 上生成两对密钥，`edge push --stack wg-nginx` 推中继，`edge link up` 装本端，只路由一段；不转发、不 NAT；`10.88`–`10.254` 归 Launcher，建议 `10.87.<n>.0/24`（待定）；集群网段和 Launcher 产品网段的潜在重叠 |
| 41 | [网段沿用 v1 和 edge setup](41.network-plan-from-v1-and-edge-setup.md) | `10.*` 归 Launcher 的应用；集群网段改成和 s1 一样的 `192.168.224.0/20` / `192.168.240.0/20`；边缘隧道 `100.127.(200+n).0/24`；网卡 `qpjoy-relay` / `qpjoy-<机器>`；`qp-tunnel-cli edge setup` 一步步问、给默认值；缺的工具先问再装 |
| 42 | [边缘机器只给了密码](42.edge-password-bootstrap-key.md) | 照 v1 的 Bootstrap Key：密码只输进 ssh 自己的提示、不保存，用一次装上推送机的 edge 密钥（`/var/lib/qp-tunnel/edge/ssh/id_ed25519`）；`edge key install`，`edge setup` 第 3、4 步会问；提示行不再写光标控制序列 |
| 43 | [边缘拓扑：只走 Domestic → Internal](43.edge-topology-domestic-to-internal.md) | s1 先不加；Domestic 之间不连，Internal 之间走 LAN；nginx 分后端、DNS 分 Domestic；共享网段 `100.127.200.0/24`，Domestic `.N`、Internal `.87+N`（s2 `.89`）；`link check` 说明握不上手的原因；`--replace` 重建隧道不删文件 |
| 44 | [边缘隧道的两套地址](44.edge-address-plans-launcher-and-isolated.md) | 默认 launcher 方案，沿用 Launcher 的编号：Internal `10.88.88.88`/`.89` 往上，Domestic `10.88.0.N`（`10.88.0.1` 留给现在那台）；只路由 `/32`，和 Launcher 的 10.88 共存；isolated 方案 `100.127.200.0/24` 保留，可以切换；真机上 internal02 → domestic02 已通 |
| 45 | [动手做 Launcher v2 之前](45.before-launcher-v2-cluster-cli-and-h2i.md) | 控制面仍只有 s2 一台，s1 以后作为 node 加入，第三台到了升三台 control，不做双 master；组件沿用 kubeadm、containerd、etcd、CoreDNS、flannel，变的是部署方式；先补镜像仓库、镜像、密钥、备份、smoke 的命令行；MX-H2I v2 以 MinCave 为底，补上旧界面的 H2O 管理、AppCenter 调试等，测试版用单独身份；domestic02 建议当 s2 那套的测试中继 |
| 46 | [项目一个个迁进本工程，Launcher 的第一步](46.project-layout-and-launcher-first-slice.md) | 和 k8s 高度集成的平台放 `architecture/`，业务项目连源码放 `projects/`，`ladder1/` 不再改；Launcher 从 L1 `1d9555e8` 拷进 `architecture/mx-launcher/`：镜像、`pg-launcher`、API、Caddy（不占宿主机端口，只信任网关带来的客户端地址）、`image` / `secret` / `app status` 命令；本机测过，没在集群上部署过 |
| 47 | [服务放哪台、去掉 Caddy、部署快路径、host-runner 和 DNS](47.scheduling-nginx-gateway-deploy-fast-path-host-runner-dns.md) | 调度器按 requests 放 Pod，人只定 GPU、service peer、数据库、分散副本，`k8s capacity` 看依据；Launcher API 不再经过应用网关，应用网关换成 nginx；`app deploy` 分检查、一次性步骤（台账、归档）、apply、滚动、验证；host-runner 和分流 DNS 在界面上操作；Launcher 把 `10.88.88.88` 写死成 Internal 的角色地址，待定 |
| 48 | [Launcher 的角色地址](48.launcher-role-addresses.md) | `10.88.88.88`（Internal）和 `10.88.0.1`（Domestic）跟着角色走：s2 那套也用 `.88`，切换时换生产 Domestic 上这个对端的公钥；边缘隧道把 `.88` 保留，s1 的边缘地址是 `.87`，s2 仍是 `.89` |
| 49 | [MinCave 的隐藏账号密码登录](49.mincave-hidden-password-login.md) | 登录页连点 5 下 logo 出现账号密码登录；客户端 `MX_H2I_MINCAVE_PASSWORD_LOGIN`、服务端 `MX_MINCAVE_PASSWORD_LOGIN_ENABLED` 两个开关，默认关；账号密码登录只是员工；客户端源码迁进 `architecture/mx-launcher/demos/mx-h2i/`，还打不了安装包 |
| 50 | [s2 的地址从环境变量取](50.s2-address-from-env.md) | s2 现在是 `192.168.0.117`，会变：`LADDER2_S2_LAN_IP`（命令前或本地 `.env`）> inventory；地址只写在 inventory，网关和探测用占位现换，Launcher 只信 Pod 网段；集群建好以后地址不能再变 |
| 51 | [NAS 先不挂，先跑内部联网](51.nas-deferred-internal-vpn-first.md) | nas、backup 两个阶段往后放；cluster 阶段只在 nas 做过时才要求 NAS；跑起 Launcher 要做的阶段；暂缓期间 etcd 和 `pg-launcher` 没有备份，切换前必须补 |
| 52 | [v2 客户端经 domestic02 连进 s2](52.domestic02-test-relay-and-ssh.md) | 照 v1：WireGuard 到 domestic02 的 `mx-domestic`，再到 s2 的 `10.88.88.88`，连上后 `ssh root@10.88.88.88`；客户端只认 HTTPS，要新域名；bootstrap 先走边缘隧道；Launcher 往外 SSH 加白名单，默认哪都连不了；装中继要用户定是否对 domestic02 开远程执行 |
| 53 | [site-slot 远程执行常开，只能到 domestic02](53.site-slot-remote-execution-on-for-domestic02.md) | 四个远程执行开关写在 `config.env` 里常开，不用每次手动开；能到哪台只由 SSH 白名单决定，s2 那套只写 domestic02；用密码装公钥、导出 WireGuard 私钥、`edge-sync` 仍然关；改了 `CLAUDE.md` 的硬约束 |
| 54 | [domestic02 的公网地址只登记一处](54.domestic02-address-maintainable.md) | `47.97.46.168`，会变：`LADDER2_DOMESTIC02_PUBLIC_IP`（命令前或本地 `.env`）> inventory；Launcher 的 SSH 白名单写占位、部署时现换；任何时候不许出现生产 Domestic 的地址；测试客户端的 `.env` 用 `client-env` 生成 |

**接着做：先读 29，再读 30、33、34。要在 s2 上动手，读 35。Launcher 和 L1 自己的服务怎么上 s2，读 36；动手做 Launcher v2 和 MX-H2I v2 之前，读 45；项目放哪、Launcher 怎么部署到 s2，读 46、47、48。加 Domestic、往边缘推送部署，读 37，再读 38、39、40、41、42、43、44。** 31、32 讲的是查看文档用的站点，不是架构。33、34 是海外的 toC 站点，大部分和 s2 无关，可以并行；NAS 读写那一段要等 s2。 第一次读：01 → 16 → 21 → 27 → 03 → 17 → 11。要动手：14 → 19 → 22 → 12。

03–14 是第一轮设计，16–20 是第二轮，21–26 是第三轮，27–28 是第四轮，30 是第五轮，33–34 是第六轮，35 是第七轮（s2 落地），36 是第八轮（Launcher 先上 L2），37 是第九轮（多台 Domestic 和 edge 工具），38 是第十轮（edge 的技术栈和系统族），39 是第十一轮（多台推送机和关系列表），40 是第十二轮（domestic02 到 internal02 的隧道），41 是第十三轮（网段沿用 v1 和 edge setup），42 是第十四轮（边缘机器只给了密码），43 是第十五轮（边缘拓扑），44 是第十六轮（边缘隧道的两套地址），45 是第十七轮（动手做 Launcher v2 之前），46 是第十八轮（项目一个个迁进本工程），47 是第十九轮（服务放哪台、去掉 Caddy、部署快路径、host-runner 和 DNS），48 是第二十轮（Launcher 的角色地址）。被后面取代的部分在各自的状态行里标明了。两处说法不一致时以编号大的为准。

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
