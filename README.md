# de-ladder2

de-llaaddddeerr 的第二层：**集群架构、自身业务，以及整套架构的知识库**。

第一层（L1）把所有服务放在一台内网服务器上。这个工程解决的是从一台变成两台、以后再加机器和云服务器：负载怎么分、高可用怎么来、数据库怎么灾备、NAS 上的静态文件怎么加缓存、别人的项目怎么接进来。

**现在的状态（2026-11-17）：四轮设计和清单骨架已写好，没有在任何服务器或集群上执行过。接着做先读 [docs/29](docs/29.handoff-and-next-steps.md)。**

## 从哪看起

- 文档索引：[docs/README.md](docs/README.md)。第一次读按 01 → 16 → 21 → 03 → 17 → 11。
- 图册：[docs/atlas/index.html](docs/atlas/index.html)，用浏览器打开。
- 所有操作：`./scripts/manage.sh help`

```bash
./scripts/manage.sh list     # 登记了哪些项目，各自迁到哪一步
./scripts/manage.sh hosts    # 登记了哪些机器
./scripts/manage.sh check    # 离线检查脚本、清单、文档
./scripts/manage.sh node plan s2   # 一台机器按角色要做哪些步骤
./scripts/manage.sh backup plan    # 备份什么、放哪
./scripts/manage.sh probe url <地址>   # 一个请求各阶段花了多久
```

## 目录

| 目录 | 内容 |
|---|---|
| `docs/` | 编号文档 `NN.xxx.md`，新决策新增一篇 |
| `docs/atlas/` | 图册：Archify 的源文件和生成的 HTML |
| `inventory/` | 主机和项目的登记。事实只写在这里，文档引用它 |
| `infra/k8s/` | 新集群的清单：kubeadm 配置、两个网关、数据库 |
| `infra/nginx/` | 边缘和宿主机 Nginx 的样板 |
| `templates/project/` | 一个项目接入集群的完整样板 |
| `services/` | L2 自己负责的服务的部署清单：迁过来的 MX 项目和平台服务（现在是空的）。结构借鉴 mx-base |
| `projects/` | 别人的业务项目的部署清单（现在是空的） |
| `console/` | L2 控制台。现在只有界面库 Neon Void，页面没建（`docs/26`） |
| `scripts/roles/` | 各角色的机器准备脚本（只有约定） |
| `scripts/manage.sh` | 统一入口 |

## 三条不能破的规矩

1. 任何改动不得影响 MX-H2I 现有用户登录和现有联网。
2. 不删旧数据。迁移只复制，清理由人在业务验收后显式执行。
3. 没实测的东西写"没测"，不写成已完成。

## 相关工程

| 工程 | 位置 | 关系 |
|---|---|---|
| L1 | `/Users/qpjoy/workspace/qpjoy/de/de-llaaddddeerr/` | 现役。MX 各项目的源码在它的 `electron-dock/` |
| 部署仓 | `/Users/qpjoy/workspace/mingxi/de-mingxi/` | 上一版的部署仓。边缘和内网 Nginx 的配置在这里，只引用 |
| cc-studio | `/Users/qpjoy/workspace/qpjoy/cc-studio/` | 网关选型和 k8s 清单的前身 |
| 外部项目 | `/Users/qpjoy/workspace/mingxi/{Night-All,po-backend-java,po-infra}` | 登记在 `inventory/projects.yaml` |
