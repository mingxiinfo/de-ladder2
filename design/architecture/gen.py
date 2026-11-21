import json
def C(i,t,l,s,r,c): return {"id":i,"type":t,"label":l,"sublabel":s,"row":r,"col":c}
def L(a,b,label=None,em=False):
    d={"from":a,"to":b}
    if label: d["label"]=label
    if em: d["variant"]="emphasis"
    return d
def doc(name,title,sub,cols,comps,conns,bounds,cards,cw=184):
    if cols==6: cw=168
    d={"schema_version":1,"diagram_type":"architecture",
       "meta":{"title":title,"subtitle":sub,"locale":"zh-CN","quality_profile":"showcase","output":f"design/architecture/{name}.html"},
       "layout":{"mode":"grid","origin":[40,90],"cols":cols,"gapX":(40 if cols==4 else 56 if cols==6 else 64),"gapY":64,"cellW":cw,"cellH":80},
       "cards":cards,"components":comps,"connections":conns,"boundaries":bounds}
    json.dump(d,open(f"design/architecture/{name}.architecture.json","w"),ensure_ascii=False,indent=1)

# ---------- 01 全景 ----------
comps=[
 C("web","external","公网用户 · toC","浏览器 / App",0,0),
 C("partner","external","合作方后端","罗盘 · Delta 调 Hub",1,0),
 C("h2i","frontend","MX-H2I 桌面端","产品网络 · 不改动",3,0),
 C("office","frontend","办公网 / 内部用户","LAN 直连",2,0),
 C("dnginx","cloud","Domestic Nginx","TLS · SNI 分域名 · 限流",0,1),
 C("wg","security","WireGuard 中继","10.88.0.1 · 100 Mbps",1,1),
 C("cdn","cloud","OSS + CDN","静态 · 视频 · 下载",4,1),
 C("hn","backend","host-nginx :80","systemd · 磁盘缓存",0,2),
 C("compose","backend","Docker Compose 应用","mx-ocr · mx-static 等",1,2),
 C("proc","backend","宿主机进程","不进集群的项目",2,2),
 C("gpub","security","Gateway public","NodePort 30080 · NGF",0,3),
 C("gint","security","Gateway internal","NodePort 30081 · 只对内",1,3),
 C("ops","backend","运维面","Headlamp · Jenkins 等",2,3),
 C("svc","backend","services/ 服务","Hub · DataPort · mx-pay",0,4),
 C("proj","backend","projects/ 业务","协作业务 · 独立命名空间",1,4),
 C("plat","backend","平台服务","Elasticsearch · Redis · HanLP",2,4),
 C("pgc","database","pg-common","CloudNativePG · Hub / DataPort",0,5),
 C("pgpay","database","pg-pay","支付 · 独立实例",1,5),
 C("pgx","database","host-pg · pg-apps","采集原始数据 · 业务项目库",2,5),
 C("s1n","backend","s1 host-nginx :80","现役 · 不改",3,2),
 C("caddy","security","mx-internal-gateway","Caddy · 8008 / 18090",3,3),
 C("launcher","backend","Launcher","身份 · 网络 · 自有 PG",3,4),
 C("nas","database","NAS","NFS · 32T · 冷存储和备份",4,5),
 C("ext","external","数据供应商 · 大模型","HTTPS 出网",4,3),
 C("oversea","cloud","Oversea toC 站点","arguseek · Delta · 见 06",4,2),
 C("oss","cloud","OSS 备份桶","每周 · 加密",4,4),
]
conns=[
 L("web","dnginx","HTTPS",True), L("partner","dnginx","HTTPS"), L("web","cdn","静态和视频"),
 L("dnginx","wg"), L("wg","hn","WireGuard",True), L("office","hn","LAN"),
 L("h2i","s1n","产品网络"), L("s1n","caddy"), L("caddy","launcher"),
 L("hn","gpub","域名在集群里",True), L("hn","compose","本机端口"), L("hn","gint","只对内的域名"),
 L("gpub","svc","HTTPRoute",True), L("gint","proj"), L("gint","ops"),
 L("svc","pgc",None,True), L("proj","pgx"), L("svc","ext","采集"),
 L("svc","launcher","令牌校验"),
 L("pgx","nas","备份直接写"), L("nas","oss","每周"), L("plat","oversea","数据往外推"),
]
bounds=[
 {"kind":"region","label":"使用方","wraps":["web","partner","office","h2i"]},
 {"kind":"region","label":"Domestic · 公网入口","wraps":["dnginx","wg"]},
 {"kind":"region","label":"s2 宿主机 · systemd / Docker","wraps":["hn","compose","proc"]},
 {"kind":"region","label":"s2 · Kubernetes（kubeadm v1.36 · flannel）","wraps":["gpub","gint","ops","svc","proj","plat","pgc","pgpay","pgx"]},
 {"kind":"region","label":"s1 · L1 单节点集群（不调整，最后迁）","wraps":["s1n","caddy","launcher"]},
]
cards=[
 {"dot":"cyan","title":"外部流量","items":["Domestic Nginx → WireGuard → host-nginx → Gateway public → 服务","视频和大文件不经 Domestic，走 OSS + CDN"]},
 {"dot":"amber","title":"内部流量","items":["办公网和 H2I 用户走 Gateway internal","MX-H2I 的登录路径仍在 s1，不改动"]},
 {"dot":"emerald","title":"不进集群的","items":["Compose 和宿主机进程由 host-nginx 转到本机端口","集群重启不影响它们"]},
]
doc("01-overview","L2 全景 · 流量怎么进来，东西在哪","设计（docs/16–28），没有在任何服务器上部署过",6,comps,conns,bounds,cards)

# ---------- 02 接入方式 ----------
comps=[
 C("hn","backend","host-nginx :80","每个域名一个配置文件",1,0),
 C("gpub","security","Gateway public","公网可达的域名",0,1),
 C("gint","security","Gateway internal","只对内的域名",1,1),
 C("fwd","backend","本机端口转发","proxy_pass 127.0.0.1:端口",2,1),
 C("svc","backend","services/<名字>","MX 项目 · HTTPRoute",0,2),
 C("proj","backend","projects/<项目>","协作业务 · k8s 部署",1,2),
 C("compose","backend","Docker Compose 应用","deploy/compose",2,2),
 C("proc","backend","宿主机进程","deploy/systemd",3,2),
 C("pg","database","pg-common · pg-pay","每个服务一个库",0,3),
 C("pgapps","database","pg-apps","业务各一个库 · 互不影响",1,3),
 C("nas","database","NAS 目录","/mnt/nas/<项目>",2,3),
 C("tpl","frontend","templates/project","拷一份改名字",0,4),
 C("manage","frontend","manage.sh app apply","必须带 --context",1,4),
 C("jenkins","frontend","Jenkins · 人 · 按钮","都调同一条命令",2,4),
 C("reg","backend","内网镜像仓库","多节点前必须有",3,4),
]
conns=[
 L("hn","gpub","进了集群",True), L("hn","gint"), L("hn","fwd","没进集群"),
 L("gpub","svc","HTTPRoute",True), L("gint","proj","HTTPRoute"),
 L("fwd","compose"), L("fwd","proc"),
 L("svc","pg"), L("proj","pgapps"), L("compose","nas"),
 L("tpl","manage"), L("jenkins","manage","触发"), L("manage","pgapps","命名空间 · 配额 · 库"),
]
bounds=[
 {"kind":"region","label":"进集群：提交清单和 HTTPRoute","wraps":["gpub","gint","svc","proj"]},
 {"kind":"region","label":"不进集群：留在宿主机，只登记和转发","wraps":["fwd","compose","proc"]},
 {"kind":"region","label":"怎么部署","wraps":["tpl","manage","jenkins","reg"]},
]
cards=[
 {"dot":"cyan","title":"业务项目进集群","items":["平台建命名空间、配额、数据库","项目自己写清单和路由，自己发布"]},
 {"dot":"amber","title":"不想容器化的","items":["原样跑在宿主机或 Compose","host-nginx 加一个域名文件转到它的端口"]},
 {"dot":"emerald","title":"迁进和回退","items":["改 host-nginx 的一行：转本机端口 ↔ 转 Gateway","秒级生效"]},
]
doc("02-onboarding","接入方式 · 宿主机、Docker、Kubernetes、业务项目","设计（docs/10、21、23、27），没有实测",5,comps,conns,bounds,cards)

# ---------- 03 演变 ----------
comps=[
 C("a1","backend","s1 · L1 集群","Launcher · H2I · 全部现役",0,0),
 C("a2","backend","s2 · 新集群","控制面 + 逐个迁入的服务",0,1),
 C("a3","database","NAS + OSS","备份先行",0,2),
 C("b1","backend","s2 · 控制面","全部主库和服务",1,0),
 C("b2","backend","s1 · 重装为节点","一级库的副本 · 无状态服务",1,1),
 C("b3","backend","GPU 节点","mx-ocr · mx-embedding 进集群",1,2),
 C("c1","backend","s2 · 控制面","etcd 1/3",2,0),
 C("c2","backend","s1 · 控制面","etcd 2/3",2,1),
 C("c3","backend","s3 · 控制面","etcd 3/3 · 自动切换",2,2),
 C("d1","cloud","Domestic 入口 × N","DNS 分流 · 不设主控",3,0),
 C("d2","cloud","toC 站点","Domestic 或 Oversea · 独立部署",3,1),
 C("d3","cloud","OSS + CDN","静态 · 视频 · 只读副本",3,2),
 C("lim","external","上限","内网上行约 300 Mbps",3,3),
 C("n1","external","现在","两个集群并存",0,3),
 C("n2","external","Launcher 迁完后","一个集群两台",1,3),
 C("n3","external","第三台内网服务器","控制面高可用",2,3),
]
conns=[
 L("a1","a2","一次迁一个服务",True), L("a2","a3","每日备份"),
 L("a2","b1","s1 迁空",True), L("b1","b2","流复制"), L("b2","b3"),
 L("b1","c1","加第三台",True), L("c1","c2"), L("c2","c3"),
 L("c1","d1","入口不够时"), L("d1","d2"), L("d2","d3","数据往外推"), L("d3","lim"),
]
bounds=[
 {"kind":"region","label":"阶段 A","wraps":["a1","a2","a3"]},
 {"kind":"region","label":"阶段 B","wraps":["b1","b2","b3"]},
 {"kind":"region","label":"阶段 C","wraps":["c1","c2","c3"]},
 {"kind":"region","label":"向外扩 · 不进集群","wraps":["d1","d2","d3"]},
]
cards=[
 {"dot":"cyan","title":"加机器是扩容还是高可用","items":["第二台：分担负载，没有自动切换","第三台内网服务器：控制面才高可用"]},
 {"dot":"amber","title":"先到的瓶颈","items":["Domestic 单台 100 Mbps","内网上行约 300 Mbps：入口最多加到三台"]},
 {"dot":"emerald","title":"toC","items":["站点放公网机器，读本地数据","内网只做源头，数据往外推"]},
]
doc("03-evolution","扩容演变 · 从两台到更多","设计（docs/16、17、21、22），没有实测",4,comps,conns,bounds,cards,cw=176)

# ---------- 04 阶段 B ----------
comps=[
 C("edge","cloud","Domestic Nginx","TLS · WireGuard 回内网",0,0),
 C("office","frontend","办公网 · H2I 用户","分流 DNS · NRPT",1,0),
 C("hn2","backend","s2 host-nginx","systemd · 坏了转 s1",0,1),
 C("hn1","backend","s1 host-nginx","重装后同样的配置",1,1),
 C("gw","security","两个 Gateway","public · internal · 两台都可达",0,2),
 C("ctrl","security","控制面 · s2","etcd 单成员 · 不自动切换",2,1),
 C("ops","backend","运维面 mx-ops","Headlamp · Grafana · Jenkins",2,2),
 C("svc2","backend","服务副本 · s2","Hub · DataPort · mx-pay",0,3),
 C("svc1","backend","服务副本 · s1","同一批服务的另一份",1,3),
 C("launcher","backend","Launcher","已迁入 · H2I 验收通过",2,3),
 C("pgp","database","主库 · s2","pg-common · pg-pay · host-pg",0,4),
 C("pgr","database","一级库副本 · s1","流复制 · 几分钟切换",1,4),
 C("nas","database","NAS","备份直接写 · 冷数据归档",2,4),
]
conns=[
 L("edge","hn2","WireGuard",True), L("edge","hn1","备用"), L("office","hn1","LAN"),
 L("hn2","gw","NodePort",True), L("hn1","gw"),
 L("gw","svc2","HTTPRoute",True), L("gw","svc1"), L("gw","launcher"),
 L("svc2","pgp",None,True), L("svc1","pgp"), L("pgp","pgr","流复制"),
 L("pgp","nas","备份"), L("ctrl","ops"),
]
bounds=[
 {"kind":"region","label":"两台都有入口","wraps":["hn2","hn1"]},
 {"kind":"region","label":"服务在两台各一份","wraps":["svc2","svc1"]},
 {"kind":"region","label":"一级库有副本","wraps":["pgp","pgr"]},
]
cards=[
 {"dot":"cyan","title":"得到什么","items":["一台机器坏了，服务在另一台继续","一级库几分钟切到副本"]},
 {"dot":"amber","title":"还没有的","items":["控制面只有 s2：坏了不能发布和调度","靠备份和 manage.sh 还原兜底"]},
 {"dot":"emerald","title":"前提","items":["L1 集群上已经没有在用的服务","s1 的数据已在 s2 上还原演练过"]},
]
doc("04-stage-b","阶段 B · s1 重装后并入，一个集群两台","设计（docs/16、21、22），没有实测",5,comps,conns,bounds,cards)

# ---------- 05 阶段 C ----------
comps=[
 C("user","external","公网用户 · toC","浏览器 / App",0,0),
 C("partner","external","合作方后端","罗盘 · Delta",1,0),
 C("e1","cloud","Domestic 入口 1","100 Mbps",0,1),
 C("e2","cloud","Domestic 入口 2 · 3","DNS 分流 · 不设主控",1,1),
 C("hn","backend","host-nginx × 3","每台一个 · 互为后备",0,2),
 C("cp1","security","s2 · 控制面","etcd 1/3",0,3),
 C("cp2","security","s1 · 控制面","etcd 2/3",1,3),
 C("cp3","security","s3 · 控制面","etcd 3/3 · 自动切换",2,3),
 C("svc","backend","服务 · 多副本","Hub · DataPort · Launcher",0,4),
 C("pg","database","主库 + 副本","一级二级都配副本",1,4),
 C("gpu","backend","GPU 服务","mx-ocr · mx-embedding · 向量化",2,4),
 C("cdn","cloud","OSS + CDN","静态 · 视频 · 大文件",0,5),
 C("site","cloud","toC 站点","Domestic 或 Oversea · 读本地",1,5),
 C("up","external","内网上行","约 300 Mbps · 总回源上限",2,5),
]
conns=[
 L("user","e1","HTTPS",True), L("partner","e2","HTTPS"), L("user","cdn","静态和视频"),
 L("e1","hn","WireGuard",True), L("e2","hn"),
 L("hn","cp1","Gateway",True), L("cp1","svc",None,True), L("cp2","pg"), L("cp3","gpu"),
 L("pg","site","数据往外推"), L("site","up"),
]
bounds=[
 {"kind":"region","label":"Domestic · 入口最多三台","wraps":["e1","e2"]},
 {"kind":"region","label":"内网集群 · 三台控制面","wraps":["cp1","cp2","cp3","svc","pg","gpu"]},
 {"kind":"region","label":"向外 · 不进集群","wraps":["cdn","site"]},
]
cards=[
 {"dot":"cyan","title":"控制面高可用","items":["三台内网服务器各一个 etcd","坏一台自动切换，不需要人"]},
 {"dot":"amber","title":"带宽上限","items":["单个入口 100 Mbps","所有入口回源共用内网约 300 Mbps"]},
 {"dot":"emerald","title":"toC 怎么扛量","items":["静态和视频走 OSS + CDN","站点读本地数据，内网只做源头"]},
]
doc("05-stage-c","阶段 C · 三台控制面，向外加入口和站点","设计（docs/16、17、30），没有实测",6,comps,conns,bounds,cards)

# ---------- 06 toC 海外站点 ----------
comps=[
 C("user","external","各地 toC 用户","国内 · 亚洲 · 欧美",0,0),
 C("bots","external","企业机器人回调","飞书 · 钉钉 · 企微",1,0),
 C("llm","external","大模型 API","站点直连",2,0),
 C("caddy","security","站点 Caddy",":443 · 每个域名一个片段",0,1),
 C("adev","backend","arguseek-dev","127.0.0.1:18080",0,2),
 C("ainh","backend","arguseek-inhouse","18081 · 以后加正式",1,2),
 C("delta","backend","Delta 海外实例","给 arguseek 新开",2,2),
 C("pga","database","arguseek PG","每个环境一个",0,3),
 C("pgd","database","Delta PG · Redis","站点本机盘",1,3),
 C("cache","database","rclone 本机缓存","读命中走本地 · 写后台传",2,3),
 C("cdn","cloud","CDN","前端静态文件",3,1),
 C("obj","cloud","同区域对象存储","每日备份 · 加密",3,3),
 C("tun","security","内网发起的隧道","只通文件服务 · 限速",2,4),
 C("dn","cloud","Domestic Nginx","hub.minsight-ai.com",1,4),
 C("hub","backend","Hub","单独的 Key 和配额",1,5),
 C("fs","backend","文件服务 · s2","rclone serve · 要鉴权",2,5),
 C("nas","database","NAS","站点只写 sites/ 目录",3,5),
]
conns=[
 L("user","caddy","接口 · 事件流",True), L("user","cdn","静态文件"), L("cdn","caddy","回源"),
 L("bots","caddy","事件回调"),
 L("caddy","adev",None,True), L("caddy","ainh"),
 L("adev","delta","同机 HTTPS",True), L("ainh","delta"),
 L("adev","pga"), L("delta","pgd"), L("delta","cache","媒体目录"),
 L("delta","llm","直连"),
 L("delta","dn","查 Hub · 跨境",True), L("dn","hub","WireGuard"),
 L("cache","tun","读未命中 · 写回",True), L("tun","fs"), L("fs","nas","NFS · LAN"),
 L("pga","obj","每日 pg_dump"), L("obj","nas","每周 · 内网拉回"),
]
bounds=[
 {"kind":"region","label":"外部","wraps":["user","bots","llm"]},
 {"kind":"region","label":"站点云服务器 · 区域待定 · Docker Compose","wraps":["caddy","adev","ainh","delta","pga","pgd","cache"]},
 {"kind":"region","label":"Domestic","wraps":["dn"]},
 {"kind":"region","label":"Internal","wraps":["hub","fs","nas"]},
]
cards=[
 {"dot":"cyan","title":"区域：访问快就行","items":["东京、新加坡优先：离国内近，大模型能直连","候选各开一台测一天，按国内晚高峰定"]},
 {"dot":"amber","title":"跨境的只有两样","items":["查 Hub：走公开接口，复用连接、设超时、加缓存","NAS 读写：本机缓存加内网发起的隧道，不用 NFS"]},
 {"dot":"emerald","title":"坏了会怎样","items":["隧道断了：缓存里的照读，新写的排队","内网断了：能登录、看历史，新查询失败"]},
]
doc("06-toc-oversea","toC 站点 · arguseek 和 Delta 在一台云服务器上","设计（docs/33、34），区域待定，没有登录过服务器",6,comps,conns,bounds,cards)

# ---------- 07 边缘机器：从任意一台 Internal 推送部署 ----------
comps=[
 C("launcher","backend","Launcher","site-slot SSH 档案",0,0),
 C("home1","database","internal01 的 home","名字 · state/ · 台账",0,1),
 C("home2","database","internal02 的 home","名字 · state/ · 台账",0,2),
 C("stacks","backend","技术栈","wg / open / hy2 · 镜像固定",0,3),
 C("o1","backend","qp-tunnel-cli edge","internal01 · s1 · CentOS 8",1,1),
 C("o2","backend","qp-tunnel-cli edge","internal02 · s2 · Ubuntu",1,2),
 C("rel","frontend","edge relations","推送机 → 机器 → 组件",1,3),
 C("jump","security","跳板机","可选 · 可多级",2,1),
 C("pre","security","preflight","系统族 · 谁管 · 别的工具",3,0),
 C("relz","database","releases/组件/版本","不覆盖 · 带 .edge-state",3,1),
 C("cur","backend","current/组件","deploy.sh → health.sh",3,2),
 C("own","database",".edge-origin","谁管 · 换人要 --take-over",3,3),
 C("d1","cloud","domestic01","internal01 管",4,0),
 C("d2","cloud","domestic02","internal02 管 · wg-nginx",4,1),
 C("d3","cloud","domestic03","internal02 管 · internal03 同理",4,2),
 C("ov","cloud","Oversea","hy2-mihomo",4,3),
 C("s2hn","backend","s2 host-nginx","edge link 回源",5,1),
]
conns=[
 L("launcher","o1","edge import"), L("launcher","o2","edge import"),
 L("home1","o1"), L("home2","o2"), L("stacks","o2","--stack"),
 L("o2","rel","只读"),
 L("o1","jump","SSH 上传",True), L("o2","jump","SSH 上传",True),
 L("jump","pre","解包到 incoming",True),
 L("pre","relz","通过才写 state"), L("relz","cur","切链接"), L("cur","own","记下推送机"),
 L("cur","d1"), L("cur","d2"), L("cur","d3"), L("cur","ov"),
 L("d2","s2hn","只走 Domestic → Internal",True),
]
bounds=[
 {"kind":"region","label":"Internal · 每台都可以是推送机","wraps":["launcher","home1","home2","stacks","o1","o2","rel"]},
 {"kind":"region","label":"每台边缘机器上 /opt/mx","wraps":["pre","relz","cur","own"]},
 {"kind":"region","label":"推出去的机器 · 不进集群","wraps":["d1","d2","d3","ov"]},
]
cards=[
 {"dot":"cyan","title":"两台推送机","items":["各有名字和 edge home，互不覆盖","机器记着谁管哪个组件，换人要 --take-over","edge relations 列出推送机 → 机器 → 组件"]},
 {"dot":"amber","title":"配置目录和隧道","items":["/var/lib/qp-tunnel/edge/state/机器/组件","不进包、不进 Git；丢了用 state pull 拿回","edge link：domestic02 10.88.0.2 → s2 10.88.88.89（只路由 /32）"]},
 {"dot":"emerald","title":"不动线上","items":["现在那台 domestic-main 有 v1 组件，整台不推","主机上不删；回退连 state 一起切回","hy2 镜像固定：v2.14.0、2.11.9-alpine"]},
]
doc("07-edge","边缘机器 · 从任意一台 Internal 经 SSH 推送","设计 + 本机容器实测（docs/37–44）；internal02 → domestic02 已在真机上通",6,comps,conns,bounds,cards)
