#!/usr/bin/env bash
# 往指定集群安装平台组件。由 ./scripts/manage.sh k8s platform 调用，不要直接运行。
# 改编自 cc-studio/infra/k8s/platform/install.sh。没有在真实集群上运行过，第一次执行时逐步核对输出。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../versions.env
source "$HERE/../versions.env"

component="${1:-}"; context="${2:-}"
[[ -n "$component" && -n "$context" ]] || { echo "用法：install.sh <gateway|postgres> <context>" >&2; exit 1; }
k() { kubectl --context "$context" "$@"; }

case "$component" in
  gateway)
    command -v helm >/dev/null || { echo "未找到 helm。" >&2; exit 1; }
    if grep -q '192.168.1.254' "$HERE/gateway/ngf-values.yaml"; then
      echo "gateway/ngf-values.yaml 里的 trustedAddresses 还是占位值，先改成实测值（docs/15）。" >&2; exit 1
    fi
    echo "▶ Gateway API CRD（与 NGINX Gateway Fabric $NGF_VERSION 配套的版本）"
    kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v$NGF_VERSION" \
      | k apply --server-side -f -
    echo "▶ NGINX Gateway Fabric $NGF_VERSION"
    helm --kube-context "$context" upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
      --version "$NGF_VERSION" --namespace nginx-gateway --create-namespace \
      --values "$HERE/gateway/ngf-values.yaml" --wait --timeout 5m
    echo "▶ Gateway"
    k apply -k "$HERE/gateway"
    k -n gateway wait --for=condition=Programmed gateway/public gateway/internal --timeout=180s
    echo "✓ 网关已就绪：public 在 $GATEWAY_PUBLIC_NODEPORT，internal 在 $GATEWAY_INTERNAL_NODEPORT"
    ;;
  postgres)
    echo "▶ CloudNativePG $CNPG_VERSION"
    k apply --server-side -f \
      "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-$CNPG_VERSION.yaml"
    k -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
    echo "▶ 数据库集群 pg-common"
    k apply -k "$HERE/postgres"
    echo "✓ 已提交。查看进度：kubectl --context $context -n data get cluster pg-common"
    ;;
  *) echo "未知组件：$component（可选 gateway、postgres）" >&2; exit 1 ;;
esac
