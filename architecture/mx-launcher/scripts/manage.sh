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
  help|-h|--help) usage ;;
  *) echo "未知命令：$cmd" >&2; usage >&2; exit 1 ;;
esac
