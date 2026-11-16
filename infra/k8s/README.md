# infra/k8s

新集群的清单。设计依据：`docs/16`（kubeadm）、`docs/18`（两个网关）、`docs/03`–`06`。

| 目录 | 内容 |
|---|---|
| `versions.env` | 所有版本号，只在这里写 |
| `cluster/` | `kubeadm-init.yaml`（第一个控制面）、`kubeadm-join.md`（加节点） |
| `platform/gateway/` | Gateway `public`、`internal` 和 NGINX Gateway Fabric 的 values |
| `platform/postgres/` | CloudNativePG 的数据库集群 `pg-common` |
| `platform/install.sh` | 由 `./scripts/manage.sh k8s platform` 调用 |

业务项目的清单不在这里，在本工程的 `projects/`。项目模板在 `templates/project/`。

## 还没做的

`./scripts/manage.sh check` 只证明清单能渲染。下面这些没在集群上跑过，或者还没写：

- 所有清单在真实集群上的行为。
- `ngf-values.yaml` 里的 `trustedAddresses` 是占位值，`install.sh` 会拒绝带着占位值安装。
- 两个 Gateway 各自映射到不同 NodePort 是否按预期工作。
- 网关和 CloudNativePG 的版本是否支持 Kubernetes v1.36。
- flannel、local-path-provisioner 的安装清单（现在只在 `docs/14` 里有步骤）。
- 备份（`docs/19`，只有设计）。
- `pg-pay`、Elasticsearch、Redis、HanLP 的清单。
- 内网镜像仓库。
- GPU 设备插件。
- 管理面：Headlamp、kube-prometheus-stack、黑盒探测的安装清单（`docs/26`，只有设计，版本没核对）。
- NFS 的 PersistentVolume、只读挂载 NAS 的文件服务（`docs/25`）。
- host-nginx 在两个节点的 NodePort 之间故障转移、维护页（`docs/23`）。
