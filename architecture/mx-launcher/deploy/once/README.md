# mx-launcher 的一次性步骤

日期：2026-11-22。状态：约定（`docs/47`）。没在集群上跑过。

这里放只需要跑一次的事：数据迁移、修复、首次初始化。`./scripts/manage.sh app deploy mx-launcher --context <名字>` 会跑还没跑过的，跑成功就记进集群里的台账（命名空间 `mx-internal-shadow` 的 ConfigMap `ladder2-once`），以后的部署直接跳过，部署不会越积越慢。

- 文件名 `NNNN-pre-<做什么>.sh`（apply 之前跑）或 `NNNN-post-<做什么>.sh`（滚动完成之后跑），编号只增不改。
- 开头写清楚：做什么、为什么只跑一次、什么时候可以归档。
- 跑失败不记台账，下次部署重跑，所以步骤要能重复执行。
- `app once list mx-launcher --context <名字>` 看哪些跑过；`app once run <步骤>` 再跑一次；`app once mark <步骤>` 只记台账不跑（人工做过的）。
- 所有要跑的集群都跑过以后，`app once archive mx-launcher --context <名字>` 把它挪进 `archive/`，在 `HISTORY.md` 记一笔。文件留在 Git 里，回头能查当时为什么做。

Schema 迁移不放这里：Launcher 自己的 TypeORM 迁移会跳过已经执行过的，每次部署由 API 的 initContainer 跑。
