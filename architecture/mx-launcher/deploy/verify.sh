#!/usr/bin/env bash
# mx-launcher 每次部署后的验证（docs/47）。只读，要快。
# 走 API server 的代理访问 Service 和 Pod，在运维机上也能跑；在 s2 本机跑时多测一段 host-nginx 的入口。
source "$LADDER2_ROOT/scripts/lib/hook.sh"
NS="$LADDER2_NAMESPACE"

ready="$(kn get clusters.postgresql.cnpg.io pg-launcher -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
if [[ "$ready" == True ]]; then ok "pg-launcher Ready"; else bad "pg-launcher 不是 Ready（${ready:-查不到}）：kubectl --context $LADDER2_CONTEXT -n $NS get cluster pg-launcher"; fi

if out="$(k get --raw "/api/v1/namespaces/$NS/services/http:mx-launcher-internal:18090/proxy/readyz" 2>&1)" && [[ "$out" == *'"ok":true'* ]]; then
  ok "Launcher API /readyz：$(grep -o '"environment":"[^"]*"' <<<"$out")"
else bad "Launcher API /readyz 不通：${out:0:200}"; fi

pod="$(kn get pod -l app.kubernetes.io/name=mx-internal-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$pod" ]] && k get --raw "/api/v1/namespaces/$NS/pods/http:$pod:8081/proxy/healthz" >/dev/null 2>&1; then ok "应用网关（nginx）$pod 健康"
else bad "应用网关不健康或没有 Pod：kubectl --context $LADDER2_CONTEXT -n $NS logs ds/mx-internal-gateway"; fi

for route in mx-launcher-api mx-launcher-apps; do
  acc="$(kn get httproute "$route" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)"
  if [[ "$acc" == True ]]; then ok "HTTPRoute $route 被 Gateway internal 接受"; else bad "HTTPRoute $route 没被接受（${acc:-没有状态}）"; fi
done

eps="$(k -n mx-dns get endpointslices -l kubernetes.io/service-name=mx-internal-coredns -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null || true)"
if [[ -n "$eps" ]]; then ok "分流 DNS 有后端：$eps"; else bad "分流 DNS 没有后端：kubectl --context $LADDER2_CONTEXT -n mx-dns get pod"; fi

# 在 s2 本机：经 host-nginx 的完整入口
if command -v curl >/dev/null 2>&1 && curl -s -o /dev/null --max-time 2 http://127.0.0.1:18090/ 2>/dev/null; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:18090/readyz || true)"
  [[ "$code" == 200 ]] && ok "host-nginx :18090 → Gateway internal → Launcher：200" || bad "host-nginx :18090 → Launcher 返回 $code"
  ip="$(awk -F= '$1=="MX_PUBLIC_BASE_URL"{print $2}' "$LADDER2_PROJECT_DIR/deploy/k8s/base/config.env" | sed -E 's#^https?://([^:/]+).*#\1#')"
  if command -v dig >/dev/null 2>&1 && ip route get "$ip" >/dev/null 2>&1; then
    ans="$(dig +short +time=2 +tries=1 @"$ip" gateway.internal.mx 2>/dev/null | head -1)"
    [[ -n "$ans" ]] && ok "分流 DNS：gateway.internal.mx → $ans（@$ip）" || warn "@$ip 问 gateway.internal.mx 没有答复（service peer 还没装的话这是正常的）"
  fi
else
  note "不在 s2 本机（或 host-nginx 还没加 18090）：跳过 host-nginx 那一段"
fi

hook_done
