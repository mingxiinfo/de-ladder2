#!/usr/bin/env bash
# mx-launcher 每次部署前的检查（docs/47）。只读，要快；不过就不部署。
# 只放"每次都可能变"的前提。装过一次就不会变的事（建集群、装 CloudNativePG、host-nginx）在 node prepare 的阶段里，
# 不在这里重复检查到底装得对不对，只看在不在。
source "$LADDER2_ROOT/scripts/lib/hook.sh"

if k get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then ok "CloudNativePG 已装"
else bad "没有 CloudNativePG：./scripts/manage.sh k8s platform postgres --context $LADDER2_CONTEXT"; fi

if k -n gateway get gateway internal >/dev/null 2>&1; then ok "Gateway internal 在"
else bad "没有 Gateway internal：./scripts/manage.sh k8s platform gateway --context $LADDER2_CONTEXT"; fi

if k get storageclass local-retain >/dev/null 2>&1; then ok "存储类 local-retain 在"
else bad "没有存储类 local-retain：./scripts/manage.sh k8s platform local-path --context $LADDER2_CONTEXT"; fi

# 必需的 Secret（deploy/secrets.list 里标了"必需"的）
while IFS='|' read -r name _keys need _note; do
  name="$(echo "$name" | xargs)"; need="$(echo "$need" | xargs)"
  [[ -z "$name" || "$name" == \#* || "$need" != 必需 ]] && continue
  if kn get secret "$name" >/dev/null 2>&1; then ok "Secret $name 在"
  elif k get namespace "$LADDER2_NAMESPACE" >/dev/null 2>&1; then
    bad "缺 Secret $name：./scripts/manage.sh secret apply mx-launcher --from <目录> --context $LADDER2_CONTEXT"
  else
    bad "命名空间 $LADDER2_NAMESPACE 还没有，Secret $name 也就没有：先 secret apply（会顺带建命名空间）"
  fi
done < <(grep -v '^[[:space:]]*#' "$LADDER2_PROJECT_DIR/deploy/secrets.list")

# host-runner 只在持有 service peer 的节点上跑。没有这个标签，管理界面里 Ensure K8s Fallback 建出来的 DaemonSet 一个 Pod 也没有
peer="$(k get nodes -l mx.ladder2/site-peer=true -o name 2>/dev/null | tr '\n' ' ')"
if [[ -n "$peer" ]]; then ok "持有 service peer 的节点：$peer"
else warn "没有节点打 mx.ladder2/site-peer=true，host-runner 起不来：kubectl --context $LADDER2_CONTEXT label node <s2 的节点名> mx.ladder2/site-peer=true（或重跑 node prepare s2 cluster）"; fi

# 在 s2 本机跑的时候，顺便看防火墙（只看，不改。docs/47 列了要放行的）
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  warn "ufw 在运行：Pod 网段到本机 19190（host-runner）、10.0.0.0/8 到 53（分流 DNS）要放行，见 docs/47"
fi

hook_done
