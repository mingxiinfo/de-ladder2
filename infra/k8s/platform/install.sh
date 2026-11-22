#!/usr/bin/env bash
# 往指定集群安装平台组件。由 ./scripts/manage.sh k8s platform 或 node prepare 调用，不要直接运行。
# 改编自 cc-studio/infra/k8s/platform/install.sh。没有在真实集群上运行过，第一次执行时逐步核对输出（docs/35）。
# 下载走 PROXY（如果设了）。每个组件都可以重复安装。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../versions.env
source "$HERE/../versions.env"
# 机器地址：环境变量 > 本地 .env > inventory（docs/50）
# shellcheck source=../../../scripts/lib/site.sh
SITE_ROOT="$(cd "$HERE/../../.." && pwd)"   # 单独一行：前缀赋值只在 source 期间有效
source "$SITE_ROOT/scripts/lib/site.sh"
site_load_env
site_check_env || exit 1

component="${1:-}"; context="${2:-}"
[[ -n "$component" && -n "$context" ]] || { echo "用法：install.sh <flannel|local-path|metrics-server|gateway|postgres> <context>" >&2; exit 1; }
k() { kubectl --context "$context" "$@"; }

# 只有下载走代理；连集群的请求不走（NO_PROXY 包含内网和集群的地址）。
NO_PROXY_LIST="localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8,.svc,.cluster.local,k8s-api.ladder2.internal"
with_proxy() {
  if [[ -n "${PROXY:-}" ]]; then
    HTTPS_PROXY="$PROXY" HTTP_PROXY="$PROXY" NO_PROXY="$NO_PROXY_LIST" https_proxy="$PROXY" http_proxy="$PROXY" no_proxy="$NO_PROXY_LIST" "$@"
  else "$@"; fi
}
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
fetch() { # fetch <地址> <存成>
  echo "  下载 $1"
  curl -fsSL --retry 3 --connect-timeout 10 ${PROXY:+--proxy "$PROXY"} -o "$WORK/$2" "$1"
}

case "$component" in
  flannel)
    echo "▶ flannel $FLANNEL_VERSION"
    fetch "https://github.com/flannel-io/flannel/releases/download/$FLANNEL_VERSION/kube-flannel.yml" flannel.yml
    # Pod 网段要和 kubeadm 的 podSubnet 一致（versions.env 的 POD_CIDR）
    sed -i.bak -E "s#\"Network\": \"[0-9./]+\"#\"Network\": \"$POD_CIDR\"#" "$WORK/flannel.yml"
    grep -q "\"Network\": \"$POD_CIDR\"" "$WORK/flannel.yml" || { echo "flannel 清单里没找到 Network 字段，格式变了" >&2; exit 1; }
    k apply -f "$WORK/flannel.yml"
    k -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=300s
    k wait --for=condition=Ready node --all --timeout=180s
    k -n kube-system rollout status deployment/coredns --timeout=180s
    echo "✓ flannel 就绪，节点 Ready，CoreDNS 就绪"
    ;;
  local-path)
    echo "▶ local-path-provisioner $LOCAL_PATH_VERSION（数据目录 /data/k8s/storage，docs/16）"
    fetch "https://raw.githubusercontent.com/rancher/local-path-provisioner/$LOCAL_PATH_VERSION/deploy/local-path-storage.yaml" local-path.yaml
    k apply -f "$WORK/local-path.yaml"
    # 上游把数据放 /opt/local-path-provisioner。只改 config.json 这一个键（用 apply 会把 setup、teardown 等键删掉），再重启让它读新配置。
    k -n local-path-storage patch configmap local-path-config --type merge --patch-file "$HERE/local-path/config-patch.json"
    k -n local-path-storage rollout restart deployment/local-path-provisioner
    k -n local-path-storage rollout status deployment/local-path-provisioner --timeout=180s
    # 本工程的默认存储类 local-retain：删 PVC 不删数据
    k apply -k "$HERE/local-path"
    echo "✓ local-path 就绪。默认存储类是 local-retain（Retain），数据在 /data/k8s/storage"
    ;;
  metrics-server)
    echo "▶ metrics-server $METRICS_SERVER_VERSION（HPA 和 kubectl top 要用）"
    fetch "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml" metrics.yaml
    # kubeadm 的 kubelet 证书是自签的。内部自用从简，不校验 kubelet 证书（docs/16、docs/35）。
    awk '{print} /- --metric-resolution=/{ match($0,/^ */); printf "%s- --kubelet-insecure-tls\n", substr($0,1,RLENGTH) }' \
      "$WORK/metrics.yaml" >"$WORK/metrics-patched.yaml"
    grep -q -- '--kubelet-insecure-tls' "$WORK/metrics-patched.yaml" || { echo "metrics-server 清单的参数格式变了，没加上 --kubelet-insecure-tls" >&2; exit 1; }
    k apply -f "$WORK/metrics-patched.yaml"
    k -n kube-system rollout status deployment/metrics-server --timeout=180s
    echo "✓ metrics-server 就绪。一两分钟后 kubectl --context $context top node 才有数"
    ;;
  gateway)
    command -v helm >/dev/null || { echo "未找到 helm。" >&2; exit 1; }
    # trustedAddresses 里的 @S2_LAN_IP@ 换成这次的地址（docs/50）。换完还有占位就不装
    site_expand "$SITE_ROOT/inventory/hosts.yaml" "$(cat "$HERE/gateway/ngf-values.yaml")" >"$WORK/ngf-values.yaml"
    if grep -q '@[A-Z0-9_]*@' "$WORK/ngf-values.yaml"; then
      echo "gateway/ngf-values.yaml 渲染后还有占位：$(grep -o '@[A-Z0-9_]*@' "$WORK/ngf-values.yaml" | sort -u | tr '\n' ' ')" >&2; exit 1
    fi
    echo "  网关信任的来源地址：$(grep -A1 'type: CIDR' "$WORK/ngf-values.yaml" | awk '$1=="value:"{print $2}' | tr '\n' ' ')（s2 的地址来自 $(site_lan_source s2)）"
    echo "▶ Gateway API CRD（与 NGINX Gateway Fabric $NGF_VERSION 配套的版本）"
    with_proxy kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v$NGF_VERSION" \
      | k apply --server-side -f -
    echo "▶ NGINX Gateway Fabric $NGF_VERSION"
    with_proxy helm --kube-context "$context" upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
      --version "$NGF_VERSION" --namespace nginx-gateway --create-namespace \
      --values "$WORK/ngf-values.yaml" --wait --timeout 5m
    echo "▶ Gateway"
    k apply -k "$HERE/gateway"
    k -n gateway wait --for=condition=Programmed gateway/public gateway/internal --timeout=180s
    echo "✓ 网关已就绪：public 在 $GATEWAY_PUBLIC_NODEPORT，internal 在 $GATEWAY_INTERNAL_NODEPORT"
    ;;
  postgres)
    echo "▶ CloudNativePG $CNPG_VERSION"
    fetch "https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_VERSION%.*}/releases/cnpg-$CNPG_VERSION.yaml" cnpg.yaml
    k apply --server-side -f "$WORK/cnpg.yaml"
    k -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
    echo "▶ 数据库集群 pg-common"
    k apply -k "$HERE/postgres"
    echo "  等 pg-common 就绪（第一次要拉镜像、初始化，最多 10 分钟）"
    k -n data wait --for=condition=Ready cluster/pg-common --timeout=600s
    echo "✓ pg-common 就绪"
    ;;
  *) echo "未知组件：$component（可选 flannel、local-path、metrics-server、gateway、postgres）" >&2; exit 1 ;;
esac
