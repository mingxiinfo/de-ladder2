# de-ladder2

de-llaaddddeerr 的第二层：集群架构、自身业务、整套架构的知识库。背景、现状和目标在 `docs/01`，不需要用户重新描述。

## 开始任何工作之前

- 接着上次做：先读 `docs/29`（现在到哪了、下一步做什么）。
- 读 `docs/README.md` 找到相关的那篇文档。架构决策都在 `docs/01`–`31`。当前整体设计的图在 `design/architecture/`，站点（演变时间线）在 `design/site/`，打成 Docker 镜像见 `docs/31`。两处说法不一致时以编号大的为准，旧文档的状态行标明了哪部分被取代。
- 机器和项目的事实只在 `inventory/hosts.yaml` 和 `inventory/projects.yaml`。标着"待确认"的字段不是事实。
- 还没决定和还没验证的事在 `docs/15`。碰到它们先问，不要自己假设。

## 硬约束

- **任何改动不得影响 MX-H2I 现有用户登录和现有联网。** s1（`mx-internal-server`）上的 Launcher 栈迁移排最后。不改 s1 上任何监听端口、地址、iptables 规则，除非用户明确要求。
- mx-pay 保持独立：专用数据库、独立发布。
- 不删旧数据。迁移只复制；任何脚本都不提供自动删除旧数据的命令。
- 本工程不拷贝 L1 的业务源码，只在 `inventory/projects.yaml` 登记并引用路径（`docs/02`）。唯一的例外是界面库 `console/ui-design/`，用户要求拷来随本工程演变（`console/README.md`）。不要修改 L1 仓库、部署仓、外部项目，除非用户明确要求。

## 术语

L1 = 现有的单机部署（s1，kubeadm）。L2 = 本工程要建的新集群（从 s2 `192.168.1.4` 开始，kubeadm v1.36，与 s1 一致）。Internal = 内网机房。Domestic = 国内公网 VPS。机器角色 control / node / site / edge 见 `docs/17`。完整术语表在 `docs/01`。

## 命名

沿用 L1 的名字，不另起别名：Launcher、Hub、DataPort、mx-common、mx-base 里各服务名；站点 Internal / Domestic / Oversea；宿主机入口 `host-nginx`；L1 的 Caddy 是 `mx-internal-gateway`。只有 L2 新增的东西有新名字（Gateway `public` / `internal`、`pg-common`、`pg-pay`、角色 control / node / site / edge）。站点是机器在哪，角色是它做什么，两回事。"网关"单独出现有歧义，写的时候带上名字（`docs/21`、`docs/23`）。

Launcher 管人和网络（身份、MX-H2I、产品网络、订阅、Oversea 节点）；L2 管机器和集群。前者的东西 L2 不重做。对 L1 的概念或以前的设定不确定时问用户，不要猜：这套方案是一步步调出来的，文档不一定全。

## 图和站点上的措辞

给人看的东西（图、站点、控制台）不用"别人的项目""别人的库"这类见外的说法，用"业务项目""协作业务"或直接写服务名（`docs/31`）。

## 命令

所有操作走 `./scripts/manage.sh`（`help` 看全部）。改完任何东西跑 `./scripts/manage.sh check`。

## 写文档的规则

- `docs/NN.xxx.md` 编号递增。新决策新增一篇并登记到 `docs/README.md`；不改写旧文档的结论，旧的过时了就在它的状态行写"已被 NN 取代"。
- 每篇第一段是 `日期：…。状态：…`。状态要说清是设计、计划，还是在哪台机器上实测过。
- 区分"源码或文档里写着"和"在服务器上看到"。本工程目前的所有内容都属于前者。
- 抄来的数字写明出处；自己估的写"估算"。
- 每篇至少一张 Mermaid 图（`docs/13`）。
- 用中文写，术语和 `inventory/` 里的名字保持一致，不另起别名。

## 改清单的规则

- 版本号只写在 `infra/k8s/versions.env`。
- `check` 只证明能渲染。没在集群上跑过的，在 `infra/k8s/README.md` 的"还没做的"里写明。
- 会修改集群的命令必须带 `--context`，不使用默认 context（s1 和 s2 是两个集群）。
- 集群里的任何东西不用 hostPort 或 hostNetwork 占宿主机的 80 / 443。入口只有两个 Gateway 的 NodePort：`public` 30080、`internal` 30081（`docs/18`）。
- 只对内网开放的应用，HTTPRoute 只挂 `internal`。不往 s1 的 Caddy 上加新路由。
- etcd 和 SQLite 不放 NFS。数据库默认不放；确实要放的登记为冷库，单副本，备份放别处（`docs/20`）。
- 云服务器和海外服务器是独立站点，不加入集群；不把公网机器放进控制面（`docs/16`、`docs/17`）。
- Git 里不放密码、token、私钥、`.ovpn`。

## 改 manage.sh 的规则

- 出网代理用环境变量 `PROXY=http://127.0.0.1:7788`。脚本不自动改 Docker 守护进程的代理：那要重启 `docker.service`，同机的 Compose 应用会跟着重启（`docs/31`）。
- 只读命令永远不改任何东西，包括不"顺手修复"。
- 查不到显示 UNKNOWN 并返回非零，不显示成"未部署"。
- `l1` 子命令只放行只读命令；`run mx-launcher` 只放行只读命令。不要放宽。
- 不加"全部部署""全部停止"和删数据的命令。
- 没实现的子命令要明说"还没实现"并指向文档，不要留空壳假装能用。
- `probe` 只发 GET 请求。不通显示"不通"并返回非零；没登记地址的层显示"未登记"，两者不混。
- 内部自用，门槛从简（`docs/16`）：交互确认只留在装平台组件和还原上。

## 容易误判的地方

- s1 的"1T 盘"其实是系统盘上的根逻辑卷，两块物理盘都约 2T。
- L1 里叫 `mx-internal-shadow` 的命名空间是正式环境，不是影子环境。
- s1 上 `127.0.0.1:5432` 的宿主机 PostgreSQL 是 Night-All / po-infra 的源数据，不是 mx-common 的数据库。
- NAS 迁移做完了不等于 mx-static 服务上线了。服务没上线。
- 两台服务器做不出自动高可用（etcd 要 3 个成员）。不要放两个控制面；已决定不设见证机，靠备份还原兜底（`docs/16`、`docs/19`）。
- **s2 不能加入 s1 的集群**：L1 的 Launcher 身份、Hub、DataPort、mx-common 部署脚本都要求节点数为 1（`docs/16` 有清单）。
- NAS 是 32T（已用 6.5T），不是 36T 或 48T。
- GPU 一共 4 块 RTX 5090，现在全在 s1（编号 0–3）。以后怎么分不固定，用户说先不考虑，不要排进计划（`docs/27`）。
- 部署清单都在本工程：L2 自己负责的服务（迁过来的 MX 项目、平台服务）在 `services/`，别人的业务项目在 `projects/`（`docs/27`）。`de-mingxi` 是上一版的部署仓，只引用，不往里加 L2 的东西。
- 副本、备份、归档是三种东西。不是每个库都配副本；每日备份直接写 NAS，不落本机盘（`docs/22`）。
- Hysteria2 是代理，不是网络：不能用它挂 NAS 或做数据库复制。Oversea 要用的数据从内往外推，不从外往里拉（`docs/24`）。
- 数据库不合并成一个实例：按"坏了影响谁"分（Launcher 的库、`pg-pay`、`pg-common`、`host-pg`）。平台管实例、备份、监控，表结构归业务（`docs/27`）。
- 运维面是一组（暂名 `mx-ops`）：L2 控制台、Headlamp、Prometheus、Grafana、黑盒探测、Jenkins。Jenkins 不再算 mx-base 的东西（`docs/30`）。
- 改了架构要同步三处：新增 `docs/NN`、改 `design/architecture/` 的源并 `diagrams`、改 `design/site/timeline.json`。然后 `design build`。
- 内网带宽约 300 Mbps：公网入口最多加到三台；备份上传和 Oversea 同步要限速（`docs/30`）。
- 采集、存储、告警用 Prometheus 这一套，不让 Launcher 自己做；Launcher 是门面，不是集群的控制面（`docs/28`）。
- 经 Domestic 的代理和用户流量共用 100 Mbps，订阅要限速；视频和大文件对外走 OSS 加 CDN（`docs/27`）。
- 控制面坏了不等于服务停了：已经在跑的 Pod 和网关继续工作。也不会自动切换到另一台（`docs/26`）。
- `infra/` 里网关和 CloudNativePG 的版本号抄自 cc-studio，没有重新核对，也没在集群上跑过。
