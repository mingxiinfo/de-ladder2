#!/usr/bin/env bash
# 项目部署钩子（deploy/preflight.sh、verify.sh、once/*.sh）共用的几个小函数（docs/47）。
# 钩子由 ./scripts/manage.sh app deploy 调用，拿到 LADDER2_CONTEXT、LADDER2_NAMESPACE 等环境变量。
set -euo pipefail
: "${LADDER2_CONTEXT:?钩子要由 ./scripts/manage.sh app deploy 调用}"
if [[ -t 1 ]]; then G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; O=$'\033[0m'; else G=""; Y=""; R=""; D=""; O=""; fi
HOOK_FAILED=0
ok()   { echo "  ${G}✓${O} $*"; }
warn() { echo "  ${Y}!${O} $*"; }
bad()  { echo "  ${R}✗${O} $*"; HOOK_FAILED=1; }
note() { echo "  ${D}$*${O}"; }
k()    { kubectl --context "$LADDER2_CONTEXT" --request-timeout=15s "$@"; }
kn()   { k -n "$LADDER2_NAMESPACE" "$@"; }
hook_done() { exit "$HOOK_FAILED"; }
