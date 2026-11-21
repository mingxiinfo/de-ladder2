# infra/k8s

新集群的清单。设计依据：`docs/16`（kubeadm）、`docs/18`（两个网关）、`docs/03`–`06`。

| 目录 | 内容 |
|---|---|
| `versions.env` | 所有版本号，只在这里写 |
| `cluster/` | `kubeadm-init.yaml`（第一个控制面）、`kubeadm-join.md`（加节点） |
| `platform/gateway/` | Gateway `public`、`internal` 和 NGINX Gateway Fabric 的 values |
| `platform/local-path/` | 默认存储类 `local-retain`（Retain）和数据目录的配置（`docs/35`） |
| `platform/postgres/` | CloudNativePG 的数据库集群 `pg-common` |
| `platform/install.sh` | 装 flannel、local-path、metrics-server、gateway、postgres。由 `k8s platform` 或 `node prepare s2 <阶段>` 调用（`docs/35`） |

业务项目的清单不在这里，在本工程的 `projects/`。项目模板在 `templates/project/`。

## 还没做的

`./scripts/manage.sh check` 只证明清单能渲染。下面这些没在集群上跑过，或者还没写：

- 所有清单和 `install.sh` 在真实集群上的行为。s2 上按 `docs/35` 的阶段第一次跑时逐个核对。
- `ngf-values.yaml` 的 `trustedAddresses` 是按原理写的（cni0 的 `192.168.224.1/32`、`192.168.1.4/32`），`node verify s2 sample` 实测。集群网段 2026-11-22 改成和 s1 一样的 `192.168.224.0/20`、`192.168.240.0/20`（`docs/41`），同样没在集群上跑过。
- 两个 Gateway 各自映射到不同 NodePort 是否按预期工作（`node verify s2 gateway` 会查）。
- 网关、CloudNativePG、local-path、metrics-server 的版本是否支持 Kubernetes v1.36。
- flannel、local-path、metrics-server 的安装是从发布页下载清单再改，没有拷进本工程；上游清单的格式变了 `install.sh` 会报错停下。
- 备份：只有 etcd 快照和 pki（`scripts/roles/control/50-backup.sh`），数据库的备份和 `backup run` 还没有（`docs/19`）。
- `pg-pay`、Elasticsearch、Redis、HanLP 的清单。
- 内网镜像仓库（`docs/15` 第 45 项）。现在用 `image import` 把镜像导入每个节点的 containerd（`docs/46`）。
- `architecture/mx-launcher` 的清单（`pg-launcher`、API、nginx 应用网关、HTTPRoute、host-runner 权限、分流 DNS）只渲染过，没在集群上 apply 过；`app deploy`、`app once` 没对真集群跑过（`docs/46`、`docs/47`）。
- GPU 设备插件。
- 管理面：Headlamp、kube-prometheus-stack、黑盒探测的安装清单（`docs/26`，只有设计，版本没核对）。
- NFS 的 PersistentVolume、只读挂载 NAS 的文件服务（`docs/25`）。
- host-nginx 在两个节点的 NodePort 之间故障转移、维护页（`docs/23`）。
