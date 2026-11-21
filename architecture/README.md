# architecture：和 k8s 高度集成的平台

日期：2026-11-22。状态：目录约定（`docs/46`）。现在只有 `mx-launcher`，没在集群上部署过。

这里放的是会自己去改集群里的东西的平台：网关路由、DNS、身份和鉴权、发布中心、往机器上推送。它们和普通业务项目不一样，所以单独放（用户 2026-11-22）。普通的业务项目放 `projects/`，没有自己源码的服务放 `services/`。

不要和 `design/architecture/` 混：那里是架构图的源文件，这里是代码。

## 每个项目的样子

```text
architecture/<名字>/
├── SOURCE.md          从 L1 哪个提交拷的、拷了哪些路径、L2 改了什么
├── README.md          怎么构建、部署、验证
├── Dockerfile         镜像（./scripts/manage.sh image build <名字>）
├── scripts/manage.sh  项目入口，只转调本工程的 ./scripts/manage.sh
├── deploy/
│   ├── secrets.list   要哪些 Secret（值不在 Git 里）
│   └── k8s/
│       ├── platform/  命名空间、配额
│       ├── bootstrap/ 只建一次、之后归应用自己改的对象
│       ├── base/
│       └── overlays/<环境>/   镜像名和版本号只写在这里
└── <源码目录>         和 L1 的目录名一致，方便以后对照
```

## 规矩

- 迁哪个才拷哪个，用 `git archive` 拷提交过的文件，拷之前扫私钥和令牌。
- L2 对源码的改动尽量小，用环境变量开关，不开时和 L1 行为一致，并写进 `SOURCE.md`。
- 不改 L1 仓库，不改 `ladder1/`（`CLAUDE.md`）。
- L1 的部署脚本（`manage.sh ops …`、`identity-*.mjs`、`k8s-*.mjs`）不拷：写死了 s1 和单节点。
