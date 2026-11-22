#!/usr/bin/env bash
# mx-launcher 在 L2 的项目入口（docs/46）。只转调本工程的 ./scripts/manage.sh，自己不改集群。
# 不是 L1 的 mx-launcher/scripts/manage.sh：那份写死了 s1、单节点、本机导入镜像，不拷过来，也不要对 s2 用（CLAUDE.md）。
#
# Launcher 的服务端按这个文件找自己的根目录（server/package.json 加 scripts/manage.sh，
# 见 server/src/modules/admin/admin.controller.ts 的 resolveMxLauncherRoot），所以它必须在这里。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
L2="$ROOT/scripts/manage.sh"

usage() {
  cat <<'EOF'
mx-launcher（architecture/mx-launcher）

  test                服务端单元测试（本机，要先 pnpm install）
  typecheck           服务端类型检查
  build               构建镜像       = ./scripts/manage.sh image build mx-launcher
  render [环境]       渲染清单       = ./scripts/manage.sh app render mx-launcher [环境]
  bootstrap-render    重新生成 deploy/k8s/bootstrap/ 的两个 ConfigMap（用 Launcher 自己的生成函数，docs/47）
  status              看集群里的状态 = ./scripts/manage.sh app status mx-launcher（要 --context）
  client-test         MinCave 客户端（demos/mx-h2i）：构建界面、跑界面测试和 L2 加的测试（要先 npm --prefix demos/mx-h2i/ui ci）
  client-package      还没实现：打安装包要 L1 的 workspace 包和 WireGuard 引擎，还没迁进来（docs/49）
  client-env [--domain <域名>]  打印测试客户端的 .env：域名默认取 inventory 里 domestic02 的 bootstrap_domain，地址按这次的取（docs/54、docs/57）

部署、导入镜像、建 Secret 都用本工程的 ./scripts/manage.sh，必须带 --context（docs/46）。
EOF
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  test)
    cd "$HERE/server"
    exec node --test --test-concurrency=4 --import tsx $(find src -name '*.test.ts' | sort) ;;
  typecheck) cd "$HERE/server" && exec npx --no-install tsc -p tsconfig.test.json ;;
  build) exec "$L2" image build mx-launcher "$@" ;;
  render) exec "$L2" app render mx-launcher "$@" ;;
  bootstrap-render) cd "$HERE/server" && exec node --import tsx "$HERE/scripts/render-bootstrap.mts" ;;
  status) exec "$L2" app status mx-launcher "$@" ;;
  client-test)
    cd "$HERE/demos/mx-h2i"
    node scripts/build-ui.mjs
    exec node --test ui/tests/*.test.mjs scripts/mincave-password-login.test.mjs scripts/ui-entry-policy.test.mjs scripts/network-diagnostic-policy.test.mjs ;;
  client-env)
    SITE_ROOT="$ROOT"; source "$ROOT/scripts/lib/site.sh"; site_load_env; site_check_env || exit 1
    domain=""
    while (( $# )); do case "$1" in --domain) domain="${2:-}"; shift 2 ;; --domain=*) domain="${1#*=}"; shift ;; *) echo "不认识的参数：$1" >&2; exit 1 ;; esac; done
    [[ -n "$domain" ]] || domain="$(site_host_field "$ROOT/inventory/hosts.yaml" domestic02 bootstrap_domain)"
    [[ -n "$domain" ]] || { echo "用法：client-env --domain <新域名>（domestic02 上配了 HTTPS 的域名，docs/52）" >&2; exit 1; }
    relay="$(site_host_field "$ROOT/inventory/hosts.yaml" domestic02 public_ip)"
    site_ssh_allowlist "$ROOT/inventory/hosts.yaml" "$relay" >/dev/null || exit 1
    cat <<ENV
# 由 architecture/mx-launcher/scripts/manage.sh client-env 生成（docs/52、docs/54）。domestic02 的地址来自 $(site_field_source domestic02 public_ip)
MX_H2I_BOOTSTRAP_BASE_URL=https://$domain
MX_H2I_HOST_RESOLVE=$domain=$relay
MX_H2I_DOMESTIC_RELAY_HOST=$relay
MX_H2I_UI=mincave
MX_H2I_MINCAVE_PASSWORD_LOGIN=1
ENV
    ;;
  client-package)
    echo "client-package 还没实现：打 MinCave 安装包要 L1 的 workspace 包（electron-launcher、tunnel 引擎、WireGuard 引擎），还没迁进来。见 docs/49。" >&2
    exit 2 ;;
  help|-h|--help) usage ;;
  *) echo "未知命令：$cmd" >&2; usage >&2; exit 1 ;;
esac
