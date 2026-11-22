# mx-launcher（L2）

日期：2026-11-22。状态：服务端、`pg-launcher`、nginx 应用网关、host-runner 权限、分流 DNS 的清单和镜像都写好了，在本机测过，**没有在 s2 或任何集群上部署过**（`docs/46`、`docs/47`）。

Launcher 管人和网络：身份和 SSO、MX-H2I、产品网络、订阅、Oversea 节点、Release Center。机器和集群归 L2（`docs/21`、`docs/28`）。

这是 s2 上的复刻，环境名 `ladder2`：
- 有自己的库；
- 切换前不连生产的 Domestic，不开 site-slot 远程执行（`docs/36`）；
- MX-H2I 的用户在切换之前一直用 s1。

来源和 L2 改了什么见 `SOURCE.md`。

## 里面有什么

| 目录 | 来源 | 用途 |
|---|---|---|
| `server/` | L1 | Launcher API（NestJS）。镜像的主体 |
| `desktop/`、`ui-design/` | L1 | 管理界面（Launcher Dashboard）的静态文件，构建时拷进镜像的 `artifacts/admin` |
| `site-slots/` | L1 | site-slot 的源文件。构建时生成产物（host-runner 要用）；Launcher 也靠它和 `scripts/manage.sh` 认自己的根目录 |
| `demos/mx-h2i/` | L1 | MX-H2I / MinCave 客户端。L2 加了隐藏的账号密码登录（`docs/49`）。界面能构建能测（`scripts/manage.sh client-test`），还打不了安装包 |
| `Dockerfile` | L2 | 一次构建出 site-slot 产物、管理界面、服务端 |
| `scripts/manage.sh` | L2 | 项目入口：`test`、`typecheck`、`build`、`render`、`bootstrap-render`、`status`、`client-test`、`client-env` |
| `deploy/k8s/` | L2 | `platform/`（命名空间 `mx-internal-shadow`、`mx-dns`）、`base/`、`dns/`、`bootstrap/`（归 Launcher 改的两个 ConfigMap）、`overlays/ladder2/` |
| `deploy/preflight.sh`、`verify.sh`、`once/` | L2 | `app deploy` 每次跑的检查和验证、只跑一次的步骤（`docs/47` 第 5 条） |
| `deploy/secrets.list` | L2 | 要哪些 Secret |

## 请求怎么走（`docs/47` 第 2 条）

| 谁 | 走哪 |
|---|---|
| H2I 客户端调 Launcher API | `<service peer>:18090` → host-nginx → Gateway internal → Launcher |
| H2I 客户端访问内网应用 | 分流 DNS 把域名解析到 service peer → host-nginx 的 80 / 8008（只放 H2I 网段）→ Gateway internal → 应用网关（nginx）→ 应用 |
| H2I 客户端查 DNS | `<service peer>:53` → kube-proxy（`externalIPs`）→ `mx-dns/mx-internal-coredns` |
| 办公网 | `http://<s2 LAN>:18090` |

service peer 是 `10.88.88.88`：Launcher 的 Internal 角色地址，跟着角色走，s2 那套也用它（`docs/48`）。s2 自己的边缘隧道地址是 `.89`，和这个无关。装 service peer 时用 s2 自己新生成的密钥，绝不用 s1 库里的。

## 在 s2 上部署

前提是 `docs/35` 的这几个阶段做完了：集群（会给 s2 打 `mx.ladder2/site-peer=true`）、local-path、网关、CloudNativePG（`k8s platform postgres`）、host-nginx。先看一遍：

```bash
sudo ./scripts/manage.sh node verify s2
```

cluster 阶段只把 kubeconfig 写给 root（`/root/.kube/ladder2.conf`）。下面不带 `sudo` 的命令用自己的用户跑，要先拷一份（已经有 `~/.kube/config` 的话不会覆盖，改用 `KUBECONFIG=~/.kube/config:~/.kube/ladder2.conf kubectl config view --flatten` 合并）：

```bash
mkdir -p ~/.kube && sudo install -m 600 -o "$USER" /root/.kube/ladder2.conf ~/.kube/ladder2.conf && { [ -e ~/.kube/config ] || cp ~/.kube/ladder2.conf ~/.kube/config; }
```

构建镜像，导入节点：

```bash
PROXY=http://127.0.0.1:7788 ./scripts/manage.sh image build mx-launcher
sudo ./scripts/manage.sh image import mx-launcher --context ladder2
```

凭据放推送机本地，不放本工程里：

```bash
sudo install -d -m 700 /var/lib/ladder2/secrets/mx-launcher/mx-internal-ops
openssl rand -hex 32 | sudo tee /var/lib/ladder2/secrets/mx-launcher/mx-internal-ops/token >/dev/null
sudo ./scripts/manage.sh secret apply mx-launcher --from /var/lib/ladder2/secrets/mx-launcher --context ladder2
```

部署：依次是检查、一次性步骤、apply、等滚动、验证，每段计时：

```bash
./scripts/manage.sh app deploy mx-launcher --context ladder2
```

host-nginx 加上 18090 和 H2I 应用入口：

```bash
sudo PROXY=http://127.0.0.1:7788 ./scripts/manage.sh node prepare s2 host-nginx
```

然后在管理界面（`http://<s2 LAN>:18090/admin/`）上：
- **Foundation → Internal Service Peer → Ensure K8s Fallback**：Launcher 建 host-runner 的 DaemonSet；
- 同一处 **Install**：host-runner 在 s2 上装 `mx-internal-svc`。s2 用自己新生成的密钥，不用 s1 库里的；
- **DNS Center → Sync / Apply**：预览、发布分流 DNS 和应用网关的配置。

看状态，包括一次性步骤的台账：

```bash
./scripts/manage.sh app status mx-launcher --context ladder2
```

s2 上没有 docker 时，在别的机器上构建好再拷过去：

```bash
./scripts/manage.sh image build mx-launcher --platform linux/amd64
./scripts/manage.sh image save mx-launcher --out mx-launcher-l2-2.tar
```

拷到 s2 以后：

```bash
sudo ./scripts/manage.sh image import mx-launcher --tar mx-launcher-l2-2.tar --context ladder2
```

## 改代码之后

1. 跑测试：

   ```bash
   cd architecture/mx-launcher/server && pnpm install
   ../scripts/manage.sh test
   ```

   现在有 2 项失败，原因见 `docs/46`"实测"。
2. 把 `deploy/k8s/overlays/ladder2/kustomization.yaml` 的 `newTag` 加一，`deploy/k8s/base/config.env` 的 `MX_INTERNAL_HOST_RUNNER_IMAGE` 跟着改。两处不一致时 `check` 会报。
3. 依次 `image build`、`image import`、`app deploy`。
4. 改了 `config.env` 里的地址或网关参数，或者改了 Launcher 生成配置的函数：跑 `scripts/manage.sh bootstrap-render`。集群里已经有这两个 ConfigMap 的话，部署不会覆盖它们，到界面上点 Apply。
5. 新加只跑一次的迁移、修复：放 `deploy/once/NNNN-pre-*.sh` 或 `NNNN-post-*.sh`，写法见 `deploy/once/README.md`。

## 还没做的

见 `docs/47`"还没做的"。最要紧的：
- 没在集群上部署过；
- 定时任务没有选主，只能 1 副本；
- `pg-launcher` 还没有每日备份。
