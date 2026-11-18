# projects：各项目的可部署清单

日期：2026-11-17。状态：目录约定。第一个放进来的是 `arguseek`（第六轮，跑在海外站点上，`docs/33`）。位置已由用户确认（2026-11-17 第三轮）：放本工程；`de-mingxi` 是上一版的部署仓，只引用。

每个要部署到新集群（或作为站点直接部署）的项目在这里有一个目录。源码不在这里，只有**怎么部署**。谁开发谁部署不变，只是文件集中在一处。

2026-11-17 第四轮：这个目录只放**别人的业务项目**。从 L1 迁过来的 MX 项目和平台服务放 `services/`（`docs/27`）。

## 结构

借鉴 L1 的 mx-base：一个服务一个目录，自带说明、部署文件和入口脚本（`docs/21`）。

```text
projects/
├── <k8s 项目>/
│   ├── README.md                    # 在哪台机器、数据在哪、怎么启停
│   ├── deploy/k8s/
│   │   ├── platform/namespace.yaml  # 平台建：命名空间、配额
│   │   ├── base/                    # kustomize base
│   │   └── overlays/production/     # 可选再加 staging
│   ├── scripts/manage.sh            # 可选：status | plan | deploy | build
│   └── docs/                        # 可选
└── <非 k8s 项目>/
    ├── README.md
    └── deploy/
        ├── nginx/<域名>.conf        # host-nginx 的转发片段
        └── compose/ 或 systemd/
```

跑在独立站点上、自带成熟发布工具的项目（比如 `arguseek`）只放 `README.md`：在哪、依赖谁、数据在哪、怎么调用它自己的发布工具、L2 补了什么。它的 Compose 文件留在原仓库，不拷，两份会走样。

新建一个 k8s 项目：`cp -r templates/project projects/<项目>`，然后按 `templates/project/README.md` 改。

## 命令

```bash
./scripts/manage.sh app list                              # services/ 和 projects/ 都列
./scripts/manage.sh app render <项目> [环境]              # 默认 production
./scripts/manage.sh app diff   <项目> [环境] --context <名字>
./scripts/manage.sh app apply  <项目> [环境] --context <名字>
```

## 放什么

只放别人的业务项目：进集群的，或者不进集群、只需要 host-nginx 转发和登记的。L2 自己负责的服务在 `services/`（`docs/27`）。

现在登记在 `inventory/projects.yaml` 里、留在 s1 不迁的外部项目（night-all、po-infra、po-backend-java）只登记，不在这里建目录。
