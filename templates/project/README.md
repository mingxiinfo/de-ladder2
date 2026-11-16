# 项目模板

日期：2026-11-17。状态：样板，没有在集群上跑过。改编自 cc-studio 的 `web-sample`。

一个无状态服务接入 L2 的完整样板。目录结构借鉴 L1 的 mx-base：一个服务一个目录，部署文件在 `deploy/` 下（`docs/21`）。

```text
deploy/k8s/
├── platform/namespace.yaml      # 平台建：命名空间、配额
├── base/                        # kustomize base：应用和 HTTPRoute
└── overlays/{staging,production}/
```

用法：

1. 自己负责的服务：`cp -r templates/project services/<名字>`，名字和 L1 里的一致。别人的业务项目：拷到 `projects/<项目>`（`docs/27`）。
2. 把 `sample` 全部换成项目名；改镜像、端口、域名。健康检查路径改成 `/healthz` 和 `/readyz`（`docs/26`）。
3. 只对内网开放的应用，把 `route.yaml` 的 `parentRefs` 从 `public` 改成 `internal`（`docs/18`）。
4. `deploy/k8s/platform/namespace.yaml` 交给平台 apply。
5. `./scripts/manage.sh app render <项目> staging` 看结果。
6. 在这个目录写一份 `README.md`：在哪台机器、数据在哪、怎么启停。需要自己的入口脚本时加 `scripts/manage.sh`，支持 `status | plan | deploy | build`（`docs/12`）。
