#!/usr/bin/env bash
# 做什么：第一次部署之后，让 Launcher 把库里的网关路由和 DNS 记录各 Apply 一次。
#   应用网关的 nginx.conf、分流 DNS 的 Corefile 就从 bootstrap 的初始内容换成 Launcher 生成的。
#   等于在管理界面的 DNS 页面上分别点一次 Apply。之后改路由、改 DNS 都在界面上做。
# 为什么只跑一次：以后的发布由界面触发。部署不该替人发布路由，否则每次部署都会把界面上没点 Apply 的改动推出去。
# 令牌不出 Pod：在 API 的 Pod 里用它自己的环境变量 MX_INTERNAL_OPS_TOKEN 调本机接口，运维机上看不到值。
# 什么时候归档：s2 这套跑过以后就可以 app once archive。
source "$LADDER2_ROOT/scripts/lib/hook.sh"
kn exec deploy/mx-launcher-internal -c internal-api -- node --input-type=module -e '
// 和管理界面 DNS 页面的 Apply 按钮发的一样（desktop/renderer.js）。serverDryRun: false 一定要写：
// 不写时接口默认只做 Kubernetes 的 server dry-run，返回 201 但 applied: false，什么都没改（s2 上第一次部署就是这样）
const post = async (path, extra = {}) => {
  const response = await fetch("http://127.0.0.1:18090" + path, {
    method: "POST",
    headers: { "content-type": "application/json", "x-mx-ops-token": process.env.MX_INTERNAL_OPS_TOKEN ?? "" },
    body: JSON.stringify({ appId: "sdk-gateway", confirmApply: true, serverDryRun: false, actor: "ladder2-once", requestId: "ladder2-once-0001", ...extra })
  });
  const body = await response.json().catch(() => ({}));
  const result = body.result ?? {};
  console.log(`  ${path} → HTTP ${response.status} ${result.status ?? ""} applied=${result.applied} ${result.message ?? body.message ?? ""}`);
  if (!response.ok || result.status === "failed" || result.applied !== true) process.exitCode = 1;
};
// k8s：写 ConfigMap mx-internal-gateway-caddy，应用网关（nginx）读它（界面上的"Caddy 80"按钮，docs/47）
await post("/internal/v1/dns/gateway/configmap/apply", { gatewayApplyBackend: "k8s" });
await post("/internal/v1/dns/coredns/configmap/apply");
'
