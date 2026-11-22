# de-ladder2

de-llaaddddeerr 的第二层：集群架构、自身业务、整套架构的知识库。背景、现状和目标在 `docs/01`，不需要用户重新描述。

## 开始任何工作之前

- 接着上次做：先读 `docs/29`（现在到哪了、下一步做什么）。
- 读 `docs/README.md` 找到相关的那篇文档。架构决策都在 `docs/01`–`30`。当前整体设计的图在 `design/architecture/`。`design/site/`、`design/deploy/` 是查看这些文档和图的站点，只是工具，不属于 L2 架构（`docs/32`）。两处说法不一致时以编号大的为准，旧文档的状态行标明了哪部分被取代。
- 机器和项目的事实只在 `inventory/hosts.yaml` 和 `inventory/projects.yaml`。标着"待确认"的字段不是事实。
- 还没决定和还没验证的事在 `docs/15`。碰到它们先问，不要自己假设。

## 硬约束

- **任何改动不得影响 MX-H2I 现有用户登录和现有联网。** Launcher 栈先在 s2 上复刻（独立的库、自己的 service peer 密钥，切换前不连生产的 Domestic；site-slot 远程执行常开，但只能到 `MX_SITE_SLOT_SSH_ALLOWED_HOSTS` 里的 domestic02，用户 2026-11-22，`docs/53`），把用户流量从 s1 切过去排最后（`docs/36`）。不改 s1 上任何监听端口、地址、iptables 规则，除非用户明确要求。
- mx-pay 保持独立：专用数据库、独立发布。
- 不删旧数据。迁移只复制；任何脚本都不提供自动删除旧数据的命令。
- **项目一个个迁进本工程**（用户 2026-11-22，`docs/46`）：和 k8s 高度集成的平台（Launcher：部署、网关、DNS、鉴权）放 `architecture/<名字>/`，迁过来的业务项目连源码放 `projects/<名字>/`，没有自己源码的服务放 `services/`。迁哪个才拷哪个，用 `git archive` 从 L1 拷提交过的文件，拷之前扫私钥和令牌，每个项目写 `SOURCE.md`（来源提交、路径、L2 改了什么）。L2 对源码的改动用环境变量开关，不开时和 L1 一样。
- `ladder1/`（L1 `pro` 分支 `0a92448` 的原样导出）只作对照，**不再改**（用户 2026-11-22）。它不进本工程的 Git（`.gitignore`，用户 2026-11-21），不要把它加回暂存区。不要修改 L1 仓库、部署仓、外部项目，除非用户明确要求。`architecture/` 和 `design/architecture/`（架构图的源）是两回事，提到时带全路径。
- 不要拿 L1 或 `ladder1/` 里的 `manage.sh` 和部署脚本对 s2 执行：它们写死了单节点、本机导入镜像和 s1 的目录。项目的清单在它自己目录的 `deploy/k8s/`，用本工程的 `app apply`、`image build|import`、`secret apply` 部署（`docs/46`）。镜像名和版本号只写在 overlay 的 `images:`，名字带仓库前缀（现在是 `localhost/`），不让节点去 Docker Hub 拉同名镜像。凭据放推送机本地（例如 `/var/lib/ladder2/secrets/<项目>/`），不放本工程里。

## 术语

L1 = 现有的单机部署（s1，kubeadm）。L2 = 本工程要建的新集群（从 s2 开始，kubeadm v1.36，与 s1 一致）。s2 的地址现在是 `192.168.0.117`，会变：执行前用 `LADDER2_S2_LAN_IP`（写在命令前或本地 `.env`）改，只在 `inventory/hosts.yaml` 写默认值，别处用 `@S2_LAN_IP@` 占位或现取；集群建好以后地址不能再变（`docs/50`）。Internal = 内网机房。Domestic = 国内公网 VPS。机器角色 control / node / site / edge 见 `docs/17`。完整术语表在 `docs/01`。

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
- 云服务器和海外服务器是独立站点，不加入集群；不把公网机器放进控制面（`docs/16`、`docs/17`）。边缘机器（Domestic、跳板机）用 L1 tunnel-cli 的 `qp-tunnel-cli edge` 从 Internal 经 SSH 推送部署，不装 Kubernetes（`docs/37`）。按技术栈用 `--stack`（wg-nginx / open-nginx / hy2-mihomo），证书、密钥、域名放推送机的 `/var/lib/qp-tunnel/edge/state/<机器>/<组件>/` 或 `--state-dir`，不进包也不进 Git（`docs/38`、`docs/39`）。每台 Internal 都能当推送机（origin），机器记着谁管哪个组件，换推送机要 `--take-over`，`edge relations` 看关系（`docs/39`）。第一次推送只推新机器，推到现在那台 Domestic 等于改生产的 H2I 边缘；v1 Launcher 推的 `current/<组件>` 不要用 `--take-over` 接管，有 v1 组件的机器不要用 `--shared-host`。
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
- s1 上不要新建 Docker 网络：默认地址池都和已有网段重叠，`docker compose` 建网络会失败（2026-11-17 在 s1 上看到）。要在 s1 上跑容器，用 host 网络，不建网络；默认只听 `127.0.0.1`。例外是查看站点：用户要求默认听 `0.0.0.0`（`docs/32`）。防火墙放行由人执行，脚本只查不改。
- NAS 是 32T（已用 6.5T），不是 36T 或 48T。
- 用户说的"双 master"是两台推送机（每台 Internal 都能往别的机器推送），不是两个 Kubernetes 控制面；控制面仍是一台（`docs/39`、`docs/16`）。
- s1 是 CentOS Linux 8（不是 Stream，已停止维护），用户定了不换系统。de-ladder2 的 `node prepare` 只有 apt 的做法，s1 并入前要补 rhel 的（`docs/39`）。
- GPU 一共 4 块 RTX 5090，现在全在 s1（编号 0–3）。以后怎么分不固定，用户说先不考虑，不要排进计划（`docs/27`）。
- 部署清单都在本工程：`architecture/`、`projects/`、`services/`（`docs/46`，取代 `docs/27` 的分法）。`de-mingxi` 是上一版的部署仓，只引用，不往里加 L2 的东西。
- 副本、备份、归档是三种东西。不是每个库都配副本；每日备份直接写 NAS，不落本机盘（`docs/22`）。
- Hysteria2 是代理，不是网络：不能用它挂 NAS 或做数据库复制。Oversea 要用的数据从内往外推，不从外往里拉（`docs/24`）。
- 边缘机器回内网的隧道用 `qp-tunnel-cli edge link`（照 L1 的 `mx-domestic` / `mx-internal-svc`：Internal 主动连出、只路由一段、不写 DNS），不用 `qp-tunnel-cli wg enroll`：那是全隧道客户端，会把 Internal 的出网和 DNS 都带走。整条流程用 `qp-tunnel-cli edge setup` 一步步问（`docs/40`、`docs/41`）。边缘机器只给了密码时，用 `edge key install` 或 `edge setup` 输一次密码，装上推送机的 edge 密钥（`/var/lib/qp-tunnel/edge/ssh/id_ed25519`）；密码不保存、不写进任何文件（`docs/42`）。
- `10.0.0.0/8` 都归 Launcher 的应用（`10.88` 中继，产品按 `10.(90+n)` 往上分），L2 不放任何东西进去；唯一的例外是边缘隧道按 Launcher 的编号用 10.88 里的 `/32`（`docs/44`）。集群网段和 s1 一样是 `192.168.224.0/20` / `192.168.240.0/20`（`docs/41`）。
- 边缘拓扑只走 Domestic → Internal：Domestic 之间不连，Internal 之间走 LAN；nginx 在后端之间分流，DNS 在 Domestic 之间切换。边缘隧道默认沿用 Launcher 的编号（`--plan launcher`）：Domestic `10.88.0.N`（domestic02 `10.88.0.2`，`10.88.0.1` 留给现在那台的 Launcher 中继），Internal `10.88.88.(87+N)`（s2 `10.88.88.89`；s1 以后加进来用 `10.88.88.87`，因为 `.88` 和 `.1` 一样是 Launcher 的角色地址，边缘隧道不能用，`docs/48`）；只路由 `/32`，不占 Launcher 的 `10.88.0.0/16`，也不用 `10.88.100.0/24`。`100.127.200.0/24`（`--plan isolated`）留给别的集群。网卡是 Domestic 上的 `qpjoy-relay`、Internal 上的 `qpjoy-<机器>`。s1 先不加进边缘网，要加必须用户明确同意（`docs/43`、`docs/44`）。
- 数据库不合并成一个实例：按"坏了影响谁"分（Launcher 的库、`pg-pay`、`pg-common`、`host-pg`）。平台管实例、备份、监控，表结构归业务（`docs/27`）。
- 运维面是一组（暂名 `mx-ops`）：L2 控制台、Headlamp、Prometheus、Grafana、黑盒探测、Jenkins。Jenkins 不再算 mx-base 的东西（`docs/30`）。
- 改了架构要同步三处：新增 `docs/NN`、改 `design/architecture/` 的源并 `diagrams`、改 `design/site/timeline.json`。想在查看站点里看到，再 `design build`。
- 查看站点（`design/`）不进架构：不登记到 `inventory/`，不接 host-nginx 和 Gateway，不画进架构图，版本号在 `design/deploy/design.env`（`docs/32`）。
- 内网带宽约 300 Mbps：公网入口最多加到三台；备份上传和 Oversea 同步要限速（`docs/30`）。
- 采集、存储、告警用 Prometheus 这一套，不让 Launcher 自己做；Launcher 是门面，不是集群的控制面（`docs/28`）。
- 经 Domestic 的代理和用户流量共用 100 Mbps，订阅要限速；视频和大文件对外走 OSS 加 CDN（`docs/27`）。
- 控制面坏了不等于服务停了：已经在跑的 Pod 和网关继续工作。也不会自动切换到另一台（`docs/26`）。
- `infra/` 里网关和 CloudNativePG 的版本号抄自 cc-studio，没有重新核对，也没在集群上跑过。
- arguseek 跑在海外云服务器 `oversea-toc` 上，不在 s1；Delta（po-infra）的正式和 dev 在 s1。海外要放 Delta 就整个实例放，不要 worker 在海外、库和 Redis 在内网。海外站点不跨境用 NFS 挂 NAS，读写走 rclone 本机缓存加内网发起的隧道，隧道的内网端放 s2、s1 不动，站点只写自己的目录；站点区域没定，按实测选（`docs/33`、`docs/34`）。
- s2 的 nas、backup 两个阶段暂缓，先跑 Launcher 的内部联网；这期间 etcd 和 `pg-launcher` 没有备份，切换用户流量前必须补（用户 2026-11-22，`docs/51`）。
- s2 第一次装用 `sudo PROXY=… ./scripts/manage.sh init s2`，按顺序做完 8 个准备阶段（失败修好再跑，做过的不重复改）；单个阶段照旧用 `node prepare`（`docs/55`）。每次上线用 `deploy <项目> --context ladder2`（在节点上用 root）：凭据第一次自动生成，镜像版本按 git 提交算、用 buildkit 直接建进 containerd，不再手改 `newTag`；基础镜像经 containerd 只拉一次（`--pull` 重拉），构建不连 Docker Hub，依赖靠层缓存不每次重装（`docs/56`）。
- s2 按 `docs/35` 的 14 个阶段落地：`node prepare s2 <阶段>` 做、`node verify s2 [阶段]` 验，一次一个阶段。机器上的阶段（host、nas、runtime、cluster、backup、host-nginx）在 s2 本机 sudo 跑，`PROXY` 写在 sudo 后面；分卷和边缘是手工的。1000 QPS 逐层压，边缘不在验收里（和 H2I 共用）。host-nginx 转 NodePort 用本机 LAN 地址，不用 127.0.0.1；数据库用存储类 `local-retain`（删 PVC 不删数据）。
- MX-H2I 3.0.0 起的新界面 MinCave（`ui/`，React）和旧界面（`src/renderer.js`）在同一个包里，共用主进程；旧界面的功能（H2O 管理、AppCenter 调试、账号密码和匿名入口）没删，只是新界面没露出来。`package.json` 一直是 2.1.20，3.0.x 是 Release Center 上的安装包版本。客户端源码在 `architecture/mx-launcher/demos/mx-h2i/`（L1 `1d9555e8`，`docs/49`），它依赖的 L1 workspace 包没迁，还打不了安装包；测试版不发到生产的 Release Center（`docs/45`）。MinCave 登录页连点 5 下 logo 出现账号密码登录，要客户端 `MX_H2I_MINCAVE_PASSWORD_LOGIN=1` 和服务端 `MX_MINCAVE_PASSWORD_LOGIN_ENABLED=1` 都开，这样登录的只是员工，不是 MinCave 管理员（`docs/49`）。
- s2 上的 Launcher API 在 host-nginx → Gateway internal 后面，不经过应用网关；客户端地址由网关按 `ngf-values.yaml` 的 `trustedAddresses` 认，Launcher 的 `MX_HTTP_TRUST_PROXY_CIDRS` 只信 Pod 网段（`docs/50`），"是不是 Domestic 中继转来的"由 host-nginx 的 18090 段判断。应用网关 `mx-internal-gateway` 是 nginx，读 Launcher 生成的 `nginx.conf`，不再是 Caddy（`docs/47`）。网关和 Corefile 的 ConfigMap 在 `bootstrap/`，归 Launcher 运行时改，`app apply` / `app deploy` 不覆盖；要重新生成用 `architecture/mx-launcher/scripts/manage.sh bootstrap-render`，不要手改。
- `10.88.88.88`（Internal）和 `10.88.0.1`（Domestic）是 Launcher 的角色地址，跟着角色走，不是某台机器的地址（用户 2026-11-22 选 A，`docs/48`）。Launcher 代码里写死它们的 72 处不改。s2 那套在自己的环境里也用 `.88`；切换是把生产 Domestic 上 `10.88.88.88/32` 对端的公钥从 s1 换成 s2，回退换回来。切换前 s2 不和生产 Domestic 握手，**s2 绝不用 s1 库里 service peer 的私钥**（密钥一样会顶掉 s1）。
- host-runner 的 DaemonSet 由 Launcher 在管理界面上建（Ensure K8s Fallback），清单只给权限，不要在清单里也建它；分流 DNS 用 Service 的 `externalIPs`，不用 hostPort / NodePort（`docs/47`）。
- s2 那套的测试中继是 domestic02（`docs/52`）。Launcher 往外 SSH 只能到 `MX_SITE_SLOT_SSH_ALLOWED_HOSTS` 里的机器，s2 的值写占位 `@DOMESTIC02_PUBLIC_IP@`，部署时按 `LADDER2_DOMESTIC02_PUBLIC_IP` > 本地 `.env` > inventory 换（现在 `47.97.46.168`，会变，`docs/54`）；不写生产的 Domestic（脚本会拒绝），也不要清空（清空就是哪都能连）；site-slot 远程执行靠它常开（`docs/53`），用密码装公钥、导出 WireGuard 私钥、`edge-sync` 仍然关。v2 客户端只认 HTTPS，远程用要在 domestic02 上配新域名。
- 部署用 `app deploy`：检查 → 一次性步骤 → apply → 等滚动 → 验证，每段计时。只跑一次的迁移、修复放项目的 `deploy/once/`，跑过记进集群里的 ConfigMap `ladder2-once`，以后跳过，跑过的用 `app once archive` 挪进 `once/archive/` 留档。每次都跑的检查只放快的（`preflight.sh`、`verify.sh`），慢的放 `verify-full.sh`。出事故后的修复不要加进部署（L1 的 deploy 就是这样变慢的，`docs/47` 第 5 条）。
- 服务放哪台交给调度器：它按 requests 放，不看实际用量，所以 requests 要写准。人只定 GPU、service peer、数据库（本地卷绑节点）、要分散的副本。依据看 `k8s capacity`（`docs/47` 第 1 条）。
- 用户问的"双 master k8s"答过了：控制面仍只有 s2，s1 等用户切走后重装、作为 node 加入，第三台内网服务器到了再升三台 control（`docs/45`、`docs/16`）。组件沿用 s1 的，不换。
