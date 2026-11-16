# services：L2 自己负责的服务

日期：2026-11-17。状态：目录约定，还没有任何服务放进来。

从 L1 迁过来的 MX 项目和平台服务在这里各有一个目录，只放**怎么部署**，源码留在 L1 的仓库（`inventory/projects.yaml` 登记路径）。别人的业务项目不放这里，放 `projects/`（`docs/27`）。

名字和 L1 一致。结构借鉴 mx-base，和 `projects/` 相同，见 `projects/README.md`。新建：`cp -r templates/project services/<名字>`。

## 计划放进来的

按 `docs/11` 的迁移顺序。目录在真正迁那个服务时再建，不提前放空壳。

| 服务 | 入口 | 数据库 | 备注 |
|---|---|---|---|
| sample | public | 无 | 样板，打通全链路用 |
| mx-rig | internal | `pg-common` 里的一个库 | 第一个迁，拿它练手 |
| mx-dataport | public | `pg-common` | |
| host-pg | 无，只有集群内地址 | 自己就是 | 宿主机 PostgreSQL 搬过来后的服务（`docs/20`） |
| mx-insight-hub | public，`/admin` 走 internal | `pg-common` | 依赖 host-pg 先搬走 |
| mx-pay | public（收银和回调），管理走 internal | `pg-pay`，独立 | |
| mx-embedding、mx-ocr、mx-static | 无或 internal | 无 | 重开或上线时 |
| mx-launcher | — | 自己的库 | 最后迁，现在不建目录 |

数据库实例怎么分见 `docs/27`。
