# mx-launcher 的来源和 L2 的改动

日期：2026-11-22。状态：已拷贝；L2 的改动在本机测过，没在集群上部署过（`docs/46`）。

## 从哪来

| 项 | 值 |
|---|---|
| 来源仓库 | `/Users/qpjoy/workspace/qpjoy/de/de-llaaddddeerr`（L1） |
| 分支 / 提交 | `pro` / `1d9555e8fba2b41ca6e5208b25ec3e691ca04d63`（2026-11-20） |
| 导出方式 | `git archive 1d9555e8 electron-dock/mx-launcher/{server,desktop,ui-design,site-slots}`，只有提交过的文件 |
| 文件数 | 315：server 221、desktop 54、ui-design 13、site-slots 27 |
| 和 `ladder1/`（`0a92448`）比 | 这四个目录只多了一个提交：`c9db16af fix: launcher release` |
| 拷之前查过 | 私钥、长令牌。只有两处 `BEGIN OPENSSH PRIVATE KEY`，是 `server/scripts/awx-api-mock-smoke.mjs`、`http-smoke.mjs` 里的假数据 |

## 没拷的

| L1 路径 | 为什么 |
|---|---|
| `scripts/`（`manage.sh`、`identity-*.mjs`、`k8s-*.mjs`、恢复脚本） | 写死了 s1、单节点、本机导入镜像（`docs/16`）。L2 用本工程的 `./scripts/manage.sh` |
| `deploy/` | L2 的清单重写在 `deploy/k8s/`（`docs/46` 第 4 条） |
| `packages/`、`demos/`（MX-H2I 客户端等）、`docs/`、`setup/` | 客户端在 MX-H2I v2 那一步再迁（`docs/45`）；文档留在 L1 |

## L2 改了源码的地方

每处都有环境变量开关，不设时和 L1 行为相同（`docs/46`、`docs/47`）。

| 文件 | 改了什么 |
|---|---|
| `server/src/config.ts` | 读 `GATEWAY_TRUSTED_PROXY_CIDRS`（逗号或空格分隔的 IPv4 CIDR，写错了启动时报错）、`GATEWAY_CLIENT_IP_HEADER`、`GATEWAY_EDGE_FORWARDED_FOR_HEADER`；导出 `parseTrustedProxyCidrs` |
| `server/src/types.ts` | `RuntimeConfig` 加三个可选字段 |
| `server/src/store/domain.ts` | `renderGatewayCaddyfile` 改成 export；设了可信代理时加 `trusted_proxies`、`trusted_proxies_strict`，边缘判断从 `remote_ip` 改成 `client_ip`，`X-Forwarded-For` 从 `{remote_host}` 改成 `{client_ip}`，边缘的原值从 host-nginx 另存的头里取 |
| `server/src/store/gateway-caddyfile-trusted-proxies.test.ts` | 新增：不设时和 L1 逐字相同；设了以后的各行；CIDR 校验 |
| `server/src/lib/trust-proxy.ts`、`server/src/index.ts` | 新增 `MX_HTTP_TRUST_PROXY_CIDRS`：Express 按地址段信任代理，优先于 `MX_HTTP_TRUST_PROXY_HOPS`；启动日志多一个 `trustProxyCidrs` 字段。`index.ts` 里原来的 `positiveInteger` 删了（只有这里用）（`docs/47` 第 2 条） |
| `server/src/lib/host-runner-node-selector.ts`、`server/src/modules/admin/admin.controller.ts` | 新增 `MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR`：Launcher 建的 host-runner DaemonSet 加 nodeSelector；`internalServicePeerHostRunnerK8sObjects` 改成 export 给测试用（`docs/47` 第 4 条） |
| `server/src/lib/l2-proxy-and-host-runner.test.ts` | 新增：信任代理的取值（用 Express 自己的 proxy-addr）、node selector 的解析、DaemonSet 只在设了时才带 nodeSelector |

## L2 新加的文件（不在 L1 里）

`Dockerfile`（`docs/47` 起多一个阶段生成 site-slot 产物）、`.dockerignore`、`scripts/manage.sh`、`scripts/render-bootstrap.mts`、`deploy/`（清单、`preflight.sh`、`verify.sh`、`once/`）、`README.md`、这份 `SOURCE.md`。

## 以后从 L1 合新提交

不自动同步。L1 有新提交时：

1. 在 L1 仓库看这几个目录改了什么：`git log --oneline 1d9555e8..pro -- electron-dock/mx-launcher/{server,desktop,ui-design,site-slots}`；
2. 逐个看 diff，挑着合进来。和上表"L2 改了源码的地方"冲突的，以 L2 的为准再补上 L1 的意图；
3. 改上面的"分支 / 提交"一行，在下面记一笔。

| 日期 | 合到 L1 的哪个提交 | 合了什么 |
|---|---|---|
| 2026-11-22 | `1d9555e8` | 第一次拷贝 |
