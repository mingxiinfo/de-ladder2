#!/usr/bin/env bash
# 项目的部署：app（清单）、image（镜像）、secret（凭据）。由 scripts/manage.sh source，不单独运行（docs/46）。
#
# 项目放三处（docs/46）：
#   architecture/<名字>/  和 k8s 高度集成的平台（现在只有 mx-launcher）：源码、镜像、清单都在这里
#   projects/<名字>/      迁过来的业务项目（源码加清单），以及别人的业务项目（只有清单）
#   services/<名字>/      没有自己源码的服务（sample）
# 一个项目的部署文件：
#   deploy/k8s/platform/   平台建的命名空间、配额（app apply 先应用）
#   deploy/k8s/bootstrap/  只在第一次创建、之后归应用自己改的对象（app apply 只在不存在时建，不覆盖）
#   deploy/k8s/base/、overlays/<环境>/   kustomize
#   deploy/secrets.list    要哪些 Secret（secret plan / apply 用，值不在 Git 里）
#   Dockerfile             有自己镜像的项目（image build 用），镜像名和版本号只写在 overlay 的 images:

APP_BASES=("$ROOT/architecture" "$ROOT/services" "${LADDER2_PROJECTS_DIR:-$ROOT/projects}")

app_dir() { # app_dir <项目> → 项目目录
  local proj="${1:-}" base
  [[ -n "$proj" ]] || die "缺少项目名。app list 看有哪些。"
  for base in "${APP_BASES[@]}"; do
    if [[ -d "$base/$proj/deploy" || -f "$base/$proj/Dockerfile" ]]; then echo "$base/$proj"; return 0; fi
  done
  die "architecture/、services/、projects/ 下都没有 $proj（非 k8s 的项目看它目录下的 README.md）"
}

app_overlay() { # app_overlay <项目> [环境] → kustomize 目录。只有一个 overlay 时可以不写环境
  local dir env="${2:-}" n=0 only="" d
  dir="$(app_dir "$1")"
  if [[ -z "$env" ]]; then
    if [[ -f "$dir/deploy/k8s/overlays/production/kustomization.yaml" ]]; then env=production
    else
      for d in "$dir"/deploy/k8s/overlays/*/; do [[ -f "$d/kustomization.yaml" ]] && { n=$((n+1)); only="$(basename "$d")"; }; done
      (( n == 1 )) || die "$1 有 $n 个环境，要写明是哪个：$(ls "$dir/deploy/k8s/overlays" 2>/dev/null | tr '\n' ' ')"
      env="$only"
    fi
  fi
  [[ -f "$dir/deploy/k8s/overlays/$env/kustomization.yaml" ]] || die "$1 没有环境 $env（$dir/deploy/k8s/overlays/$env/kustomization.yaml）"
  echo "$dir/deploy/k8s/overlays/$env"
}

app_namespace() { # app_namespace <overlay 目录> → 主命名空间：overlay 写了用 overlay 的，否则用 base 的
  local ns; ns="$(awk '/^namespace:/{print $2; exit}' "$1/kustomization.yaml")"
  [[ -n "$ns" ]] || ns="$(awk '/^namespace:/{print $2; exit}' "$1/../../base/kustomization.yaml" 2>/dev/null)"
  [[ -n "$ns" ]] || die "$1/kustomization.yaml 和 base 都没有写 namespace:"
  echo "$ns"
}

app_namespaces() { # app_namespaces <overlay 目录> → 渲染结果里出现的全部命名空间（一个项目可以跨几个，例如 mx-launcher 的 mx-dns）
  kubectl kustomize "$1" | awk '/^  namespace: /{print $2}' | sort -u
}

app_workloads() { # app_workloads <overlay 目录> → 每行：kind/name namespace（Deployment、DaemonSet、StatefulSet）
  kubectl kustomize "$1" | awk '
    /^---/ { if (k != "" && n != "") print k "/" n, ns; k=""; n=""; ns=""; inmeta=0; next }
    /^kind: (Deployment|DaemonSet|StatefulSet)$/ { k=tolower($2) }
    /^metadata:/ { inmeta=1; next }
    /^[a-z]/ { inmeta=0 }
    inmeta && /^  name: / && n == "" { n=$2 }
    inmeta && /^  namespace: / { ns=$2 }
    END { if (k != "" && n != "") print k "/" n, ns }'
}

# 机器地址的占位（docs/54）：项目 deploy/k8s 下 *.env 里的 @<主机>_LAN_IP@、@<主机>_PUBLIC_IP@，
# 渲染和部署前换成这次的地址（环境变量 > 本地 .env > inventory，scripts/lib/site.sh）。
# 换在临时拷贝里，不改本工程的文件；ConfigMap 的名字带内容的哈希，地址变了 Pod 会跟着滚动。
APP_RUN_TMP=""
app_tmp_init() { # 在主 shell 里调用（不能在 $(...) 里），临时目录随进程退出删除
  [[ -n "$APP_RUN_TMP" ]] && return 0
  APP_RUN_TMP="$(mktemp -d)"
  trap 'rm -rf "$APP_RUN_TMP"' EXIT
}
app_site_overlay() { # app_site_overlay <overlay 目录> → 换好地址的 overlay 目录；没有占位就原样返回
  local ov="$1" k8s rel out f
  k8s="$(cd "$ov/../.." && pwd)"
  grep -rlE '@[A-Z0-9_]+_(LAN|PUBLIC)_IP@' "$k8s" --include='*.env' >/dev/null 2>&1 || { echo "$ov"; return 0; }
  [[ -n "$APP_RUN_TMP" ]] || die "内部错误：app_site_overlay 之前要先 app_tmp_init"
  out="$APP_RUN_TMP/$(basename "$(cd "$k8s/../.." && pwd)")-k8s"
  if [[ ! -d "$out" ]]; then
    cp -R "$k8s" "$out"
    while IFS= read -r f; do
      site_expand "$INV_HOSTS" "$(cat "$f")" >"$f.new" || die "$f 里的地址占位换不掉（见上一行）"
      printf '\n' >>"$f.new"; mv "$f.new" "$f"
    done < <(grep -rlE '@[A-Z0-9_]+_(LAN|PUBLIC)_IP@' "$out" --include='*.env')
    # 任何 SSH 白名单（*_SSH_ALLOWED_HOSTS）换完地址后都不许有生产 Domestic 的地址，app apply / diff / render 都挡（docs/54）
    local line
    while IFS= read -r line; do
      site_ssh_allowlist "$INV_HOSTS" "${line#*=}" >/dev/null || die "拒绝：${line%%=*} 换完地址是 ${line#*=}（docs/54）"
    done < <(grep -rhE '^[A-Z0-9_]*SSH_ALLOWED_HOSTS=' "$out" --include='*.env')
  fi
  rel="$(cd "$ov" && pwd)"; rel="${rel#"$k8s"/}"
  echo "$out/$rel"
}

# app_apply_all <项目目录> <overlay> <ctx>：platform/ → bootstrap/ 里集群还没有的 → overlay
app_apply_all() {
  local dir="$1" ov="$2" ctx="$3" f
  if [[ -d "$dir/deploy/k8s/platform" ]]; then
    echo "▶ 平台：命名空间、配额"
    kubectl --context "$ctx" apply -f "$dir/deploy/k8s/platform"
  fi
  if [[ -d "$dir/deploy/k8s/bootstrap" ]]; then
    echo "▶ 只建一次的对象（已有的不覆盖，归应用自己改）"
    for f in "$dir"/deploy/k8s/bootstrap/*.yaml; do
      [[ -f "$f" ]] || continue
      if kubectl --context "$ctx" get -f "$f" -o name >/dev/null 2>&1; then
        echo "  = $(basename "$f")：已存在，不动"
      else
        kubectl --context "$ctx" create -f "$f"
      fi
    done
  fi
  local sov; sov="$(app_site_overlay "$ov")" || exit 1
  echo "▶ 与集群 ${B}$ctx${O} 的差异："
  kubectl --context "$ctx" diff -k "$sov" || true
  kubectl --context "$ctx" apply -k "$sov"
}

app_image_ref() { # app_image_ref <overlay 目录> → newName:newTag（images: 的第一条）
  local name tag
  name="$(awk '/^images:/{i=1;next} /^[a-z]/{i=0} i && $1=="newName:"{print $2; exit}' "$1/kustomization.yaml")"
  tag="$(awk '/^images:/{i=1;next} /^[a-z]/{i=0} i && $1=="newTag:"{print $2; exit}' "$1/kustomization.yaml")"
  [[ -n "$name" && -n "$tag" ]] || die "$1/kustomization.yaml 的 images: 里没有 newName / newTag"
  echo "$name:$tag"
}

# 位置参数里去掉 --context 和它的值，剩下的给子命令用
app_positional() {
  while (( $# )); do
    case "$1" in --context) shift 2 || true ;; --context=*) shift ;; *) printf '%s\n' "$1"; shift ;; esac
  done
}

# ---------- secrets.list ----------

secrets_list() { # secrets_list <项目目录> → 每行：名字<TAB>键<TAB>必需|可选
  local f="$1/deploy/secrets.list"
  [[ -f "$f" ]] || return 0
  awk -F'|' '/^[[:space:]]*#/ || NF < 3 {next}
    { for (i=1;i<=3;i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) } print $1 "\t" $2 "\t" $3 }' "$f"
}

secret_exists() { # secret_exists <ctx> <ns> <名字>：0 有，1 没有，2 查不到
  local out
  out="$(kubectl --context "$1" -n "$2" --request-timeout=10s get secret "$3" -o name 2>&1)" && return 0
  [[ "$out" == *NotFound* || "$out" == *"not found"* ]] && return 1
  return 2
}

app_warn_missing_secrets() { # 部署后提醒还缺的必需 Secret（不拦）
  local dir="$1" ctx="$2" ns="$3" name keys need missing=()
  while IFS=$'\t' read -r name keys need; do
    [[ "$need" == 必需 ]] || continue
    secret_exists "$ctx" "$ns" "$name" || missing+=("$name")
  done < <(secrets_list "$dir")
  if (( ${#missing[@]} )); then
    warn "还缺必需的 Secret：${missing[*]}。Pod 会停在 CreateContainerConfigError，补上后自己恢复："
    echo "      ./scripts/manage.sh secret plan $(basename "$dir") --from <目录> --context $ctx"
  fi
}

# ---------- app ----------

cmd_app() {
  local sub="${1:-list}"; shift || true
  app_tmp_init
  local pos=() a
  while IFS= read -r a; do pos+=("$a"); done < <(app_positional "$@")
  case "$sub" in
    list)
      local base d n=0
      for base in "${APP_BASES[@]}"; do
        for d in "$base"/*/; do
          [[ -d "$d" ]] || continue
          printf "%-13s %s\n" "$(basename "$base")" "$(basename "$d")"; n=$((n+1))
        done
      done
      (( n )) || echo "（还没有。见 docs/46）" >&2 ;;
    render)
      local sov; sov="$(app_site_overlay "$(app_overlay "${pos[0]:-}" "${pos[1]:-}")")" || exit 1
      kubectl kustomize "$sov" ;;
    diff)
      local ov ctx sov; ov="$(app_overlay "${pos[0]:-}" "${pos[1]:-}")"; ctx="$(need_context "$@")"
      sov="$(app_site_overlay "$ov")" || exit 1
      kubectl --context "$ctx" diff -k "$sov" || true ;;
    apply)
      local dir ov ctx ns
      dir="$(app_dir "${pos[0]:-}")"; ov="$(app_overlay "${pos[0]:-}" "${pos[1]:-}")"; ctx="$(need_context "$@")"
      ns="$(app_namespace "$ov")"
      app_apply_all "$dir" "$ov" "$ctx"
      app_warn_missing_secrets "$dir" "$ctx" "$ns"
      echo "${D}只 apply，不等滚动、不跑检查。完整的一次部署用 app deploy（docs/47）。看状态：app status ${pos[0]} --context $ctx${O}" ;;
    deploy) app_deploy "$@" ;;
    once) app_once "$@" ;;
    status)
      local dir ov ctx ns rc=0
      dir="$(app_dir "${pos[0]:-}")"; ov="$(app_overlay "${pos[0]:-}" "${pos[1]:-}")"; ctx="$(need_context "$@")"
      ns="$(app_namespace "$ov")"
      local k=(kubectl --context "$ctx" -n "$ns" --request-timeout=10s) other
      echo "${B}${pos[0]}${O}  命名空间 $ns  集群 $ctx  镜像 $(app_image_ref "$ov" 2>/dev/null || echo 无)"
      "${k[@]}" get deploy,daemonset,statefulset,pod,svc,pvc -o wide || { echo "UNKNOWN：查不到命名空间 $ns（连不上集群，或还没 app apply）"; return 2; }
      for other in $(app_namespaces "$ov"); do
        [[ "$other" == "$ns" ]] && continue
        echo "${B}命名空间 $other${O}"
        kubectl --context "$ctx" -n "$other" --request-timeout=10s get deploy,daemonset,pod,svc -o wide || { echo "  UNKNOWN"; rc=2; }
      done
      echo "${B}路由${O}";       "${k[@]}" get httproute 2>/dev/null || echo "  UNKNOWN（没有 Gateway API，或查不到）"
      echo "${B}数据库集群${O}"; "${k[@]}" get clusters.postgresql.cnpg.io 2>/dev/null || echo "  UNKNOWN（没有 CloudNativePG，或查不到）"
      app_once_ledger_show "$dir" "$ctx" "$ns" || true
      local name keys need state
      if [[ -n "$(secrets_list "$dir")" ]]; then
        echo "${B}Secret${O}（只看有没有，不看值）"
        while IFS=$'\t' read -r name keys need; do
          if secret_exists "$ctx" "$ns" "$name"; then state="${G}有${O}"
          else case $? in 1) state="$([[ $need == 必需 ]] && echo "${R}没有${O}" || echo "${D}没有${O}")"; [[ $need == 必需 ]] && rc=1 ;; *) state="UNKNOWN"; rc=2 ;; esac
          fi
          printf "  %-32s %-4s %b\n" "$name" "$need" "$state"
        done < <(secrets_list "$dir")
      fi
      return $rc ;;
    *) die "用法：app list | render <项目> [环境] | diff|apply|deploy|status <项目> [环境] --context <名字> | once list|run|mark|archive <项目> …" ;;
  esac
}

# ---------- deploy：快的那条路（docs/47） ----------
#
# 一次部署 = 检查（preflight）→ 还没跑过的一次性步骤（once，pre-）→ apply → 等滚动 → 一次性步骤（post-）→ 验证（verify）。
# 每一段打印耗时，慢在哪一眼能看出来。
#
#   deploy/preflight.sh   每次都跑，要快：前提在不在（CRD、Secret、节点标签、镜像在不在节点上）。失败就停
#   deploy/verify.sh      每次都跑，要快：服务起来没有、入口通不通。失败返回非零
#   deploy/verify-full.sh 只在 --full 时跑：慢的检查（压测、逐条路由）
#   deploy/once/NNNN-pre-*.sh、NNNN-post-*.sh
#                         只跑一次的迁移、修复、首次初始化。跑成功就记进集群里的台账（ConfigMap ladder2-once），
#                         以后的部署跳过。跑过的可以 app once archive 挪进 once/archive/，并在 once/HISTORY.md 记一笔，
#                         文件留在 Git 里，回头能查当时为什么做、做了什么。
# 钩子脚本拿到的环境变量：LADDER2_ROOT、LADDER2_CONTEXT、LADDER2_NAMESPACE、LADDER2_PROJECT_DIR、LADDER2_OVERLAY。

ONCE_LEDGER=ladder2-once

app_hook() { # app_hook <脚本> <dir> <ov> <ctx> <ns>：跑项目自己的钩子
  local script="$1" dir="$2" ov="$3" ctx="$4" ns="$5"
  LADDER2_ROOT="$ROOT" LADDER2_CONTEXT="$ctx" LADDER2_NAMESPACE="$ns" LADDER2_PROJECT_DIR="$dir" LADDER2_OVERLAY="$ov" \
    bash "$script"
}

app_once_get() { # app_once_get <ctx> <ns> <步骤名> → 打印台账里的记录（没有就空）；台账不存在返回 1，查不到返回 2
  local out
  # 步骤名以数字开头、带连字符，jsonpath 解析不了，用 go-template 的 index
  out="$(kubectl --context "$1" -n "$2" --request-timeout=10s get configmap "$ONCE_LEDGER" \
          -o "go-template={{with .data}}{{index . \"$3\"}}{{end}}" 2>&1)" \
    || { [[ "$out" == *NotFound* ]] && return 1; return 2; }
  [[ "$out" == "<no value>" ]] && out=""
  printf '%s' "$out"
}

app_once_done() { # app_once_done <ctx> <ns> <步骤名> → 0 跑过，1 没跑过，2 查不到
  local out rc=0
  out="$(app_once_get "$1" "$2" "$3")" || rc=$?
  (( rc == 2 )) && return 2
  [[ -n "$out" ]]
}

app_once_record() { # app_once_record <ctx> <ns> <步骤名> <说明>
  local ctx="$1" ns="$2" step="$3" note="$4"
  kubectl --context "$ctx" -n "$ns" get configmap "$ONCE_LEDGER" >/dev/null 2>&1 \
    || kubectl --context "$ctx" -n "$ns" create configmap "$ONCE_LEDGER" >/dev/null
  kubectl --context "$ctx" -n "$ns" patch configmap "$ONCE_LEDGER" --type merge \
    -p "{\"data\":{\"$step\":\"$note\"}}" >/dev/null
}

app_once_steps() { # app_once_steps <dir> [pre|post] → 还在 once/ 里（没归档）的步骤文件，按编号排序
  local dir="$1" phase="${2:-}" f
  for f in "$dir"/deploy/once/[0-9][0-9][0-9][0-9]-*.sh; do
    [[ -f "$f" ]] || continue
    case "$phase" in pre) [[ "$(basename "$f")" == ????-pre-* ]] || continue ;; post) [[ "$(basename "$f")" == ????-post-* ]] || continue ;; esac
    echo "$f"
  done
}

app_once_run_pending() { # app_once_run_pending <dir> <ov> <ctx> <ns> <pre|post>
  local dir="$1" ov="$2" ctx="$3" ns="$4" phase="$5" f step rev n=0
  rev="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
  while IFS= read -r f; do
    step="$(basename "$f" .sh)"
    if app_once_done "$ctx" "$ns" "$step"; then continue; fi
    case $? in 2) bad "查不到一次性步骤的台账（$ns/$ONCE_LEDGER），不跑 $step"; return 1 ;; esac
    echo "  ▷ 一次性步骤 $step（第一次跑）"
    app_hook "$f" "$dir" "$ov" "$ctx" "$ns" || { bad "$step 失败，没有记进台账；修好后再部署会重跑"; return 1; }
    app_once_record "$ctx" "$ns" "$step" "$(date -u +%Y-%m-%dT%H:%M:%SZ) $rev"
    ok "$step 记进台账"; n=$((n+1))
  done < <(app_once_steps "$dir" "$phase")
  (( n )) || echo "  ${D}没有要跑的（$phase）${O}"
}

app_once_ledger_show() { # app_once_ledger_show <dir> <ctx> <ns>
  local dir="$1" ctx="$2" ns="$3" f step state archived
  [[ -d "$dir/deploy/once" ]] || return 0
  echo "${B}一次性步骤${O}（台账 $ns/$ONCE_LEDGER）"
  while IFS= read -r f; do
    step="$(basename "$f" .sh)"
    state="$(app_once_get "$ctx" "$ns" "$step")" || { [[ $? == 2 ]] && state="UNKNOWN"; }
    printf "  %-48s %s\n" "$step" "${state:-${Y}还没跑${O}}"
  done < <(app_once_steps "$dir")
  archived="$(find "$dir/deploy/once/archive" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')"
  (( archived )) && echo "  ${D}已归档 $archived 个（deploy/once/archive/，记录在 once/HISTORY.md）${O}"
  return 0
}

app_deploy() {
  local pos=() a full=0
  while IFS= read -r a; do [[ "$a" == --full ]] && { full=1; continue; }; pos+=("$a"); done < <(app_positional "$@")
  local dir ov ctx ns t0 t rc=0
  dir="$(app_dir "${pos[0]:-}")"; ov="$(app_overlay "${pos[0]:-}" "${pos[1]:-}")"; ctx="$(need_context "$@")"
  ns="$(app_namespace "$ov")"
  t0=$SECONDS; t=$SECONDS
  lap() { echo "  ${D}⏱ $1：$((SECONDS - t)) 秒${O}"; t=$SECONDS; }
  echo "${B}部署 ${pos[0]}${O} → 集群 $ctx（$(basename "$ov")，$(app_image_ref "$ov" 2>/dev/null || echo 没有自己的镜像)）"

  echo "${B}1. 检查${O}"
  app_deploy_image_check "$ov" "$ctx" || rc=1
  if [[ -f "$dir/deploy/preflight.sh" ]]; then app_hook "$dir/deploy/preflight.sh" "$dir" "$ov" "$ctx" "$ns" || rc=1; fi
  (( rc == 0 )) || die "检查没过，没有部署。"
  lap 检查

  echo "${B}2. 一次性步骤（apply 之前）${O}"
  app_apply_namespaces "$dir" "$ctx"
  app_once_run_pending "$dir" "$ov" "$ctx" "$ns" pre || die "一次性步骤失败，没有部署。"
  lap 一次性步骤

  echo "${B}3. apply${O}"
  app_apply_all "$dir" "$ov" "$ctx"
  lap apply

  echo "${B}4. 等滚动完成${O}"
  local w kind_name wns
  while read -r kind_name wns; do
    [[ -n "$kind_name" ]] || continue
    if kubectl --context "$ctx" -n "${wns:-$ns}" rollout status "$kind_name" --timeout=300s; then ok "${wns:-$ns}/$kind_name"
    else bad "${wns:-$ns}/$kind_name 没有在 5 分钟内就绪：kubectl --context $ctx -n ${wns:-$ns} describe $kind_name"; rc=1; fi
  done < <(app_workloads "$ov")
  lap 滚动

  echo "${B}5. 一次性步骤（apply 之后）${O}"
  if (( rc == 0 )); then app_once_run_pending "$dir" "$ov" "$ctx" "$ns" post || rc=1
  else echo "  ${D}滚动没完成，跳过${O}"; fi
  lap 一次性步骤

  echo "${B}6. 验证${O}"
  if [[ -f "$dir/deploy/verify.sh" ]]; then app_hook "$dir/deploy/verify.sh" "$dir" "$ov" "$ctx" "$ns" || rc=1; else echo "  ${D}项目没有 deploy/verify.sh${O}"; fi
  if (( full )) && [[ -f "$dir/deploy/verify-full.sh" ]]; then app_hook "$dir/deploy/verify-full.sh" "$dir" "$ov" "$ctx" "$ns" || rc=1; fi
  lap 验证

  echo
  if (( rc )); then echo "${R}部署完成但有失败项${O}（共 $((SECONDS - t0)) 秒）"; return 1; fi
  echo "${G}部署完成${O}（共 $((SECONDS - t0)) 秒）"
}

app_apply_namespaces() { # 一次性步骤的台账放在命名空间里，pre 步骤之前命名空间要先有
  local dir="$1" ctx="$2"
  [[ -d "$dir/deploy/k8s/platform" ]] && kubectl --context "$ctx" apply -f "$dir/deploy/k8s/platform" >/dev/null
  return 0
}

app_deploy_image_check() { # 有自己镜像的项目：节点上有没有 overlay 要的版本（kubelet 上报的镜像列表，不用 root）
  local ov="$1" ctx="$2" ref names
  ref="$(app_image_ref "$ov" 2>/dev/null)" || return 0
  names="$(kubectl --context "$ctx" --request-timeout=10s get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.images[*].names}{"\n"}{end}' 2>/dev/null)" \
    || { warn "UNKNOWN：查不到节点上的镜像"; return 0; }
  if grep -qF "$ref" <<<"$names"; then ok "节点上有 $ref（$(grep -F "$ref" <<<"$names" | cut -f1 | tr '\n' ' ')）"
  else
    bad "节点上没有 $ref。先 image build、在节点上 sudo image import（kubelet 只上报最多 50 个镜像，镜像很多时这里可能看不到）"
    return 1
  fi
}

app_once() { # app once list|run|mark|archive <项目> [步骤] --context <名字>
  local sub="${1:-list}"; shift || true
  local pos=() a
  while IFS= read -r a; do pos+=("$a"); done < <(app_positional "$@")
  local dir ov ctx ns f step
  dir="$(app_dir "${pos[0]:-}")"; ov="$(app_overlay "${pos[0]:-}" "")"; ctx="$(need_context "$@")"; ns="$(app_namespace "$ov")"
  case "$sub" in
    list) app_once_ledger_show "$dir" "$ctx" "$ns" ;;
    run|mark)
      step="${pos[1]:-}"; [[ -n "$step" ]] || die "用法：app once $sub ${pos[0]} <步骤名> --context $ctx"
      f="$dir/deploy/once/${step%.sh}.sh"; [[ -f "$f" ]] || die "没有 $f"
      step="$(basename "$f" .sh)"
      if [[ "$sub" == run ]]; then
        app_once_done "$ctx" "$ns" "$step" && warn "$step 已经跑过，按你的要求再跑一次"
        app_hook "$f" "$dir" "$ov" "$ctx" "$ns" || die "$step 失败，没有记进台账"
      fi
      app_once_record "$ctx" "$ns" "$step" "$(date -u +%Y-%m-%dT%H:%M:%SZ) $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)$([[ $sub == mark ]] && echo ' marked')"
      ok "$step 记进台账（$ns/$ONCE_LEDGER）" ;;
    archive)
      # 在这个集群跑过的挪进 archive/，留在 Git 里。别的集群还要跑的话，先在那边跑完再归档
      mkdir -p "$dir/deploy/once/archive"
      local hist="$dir/deploy/once/HISTORY.md" n=0 state
      [[ -f "$hist" ]] || printf '# 已归档的一次性步骤\n\n| 步骤 | 在哪个集群跑的 | 台账记录 |\n|---|---|---|\n' >"$hist"
      while IFS= read -r f; do
        step="$(basename "$f" .sh)"
        state="$(app_once_get "$ctx" "$ns" "$step")" || state=""
        [[ -n "$state" ]] || continue
        mv "$f" "$dir/deploy/once/archive/"
        printf '| %s | %s | %s |\n' "$step" "$ctx" "$state" >>"$hist"
        echo "  → archive/$step.sh"; n=$((n+1))
      done < <(app_once_steps "$dir")
      echo "归档了 $n 个。台账里的记录不删：以后部署照样知道它们跑过" ;;
    *) die "用法：app once list|run|mark|archive <项目> [步骤] --context <名字>" ;;
  esac
}

# ---------- image ----------

cmd_image() {
  local sub="${1:-}"; shift || true
  local pos=() a
  while IFS= read -r a; do pos+=("$a"); done < <(app_positional "$@")
  local proj="${pos[0]:-}"
  [[ -n "$proj" ]] || die "用法：image build|save|import|list <项目> …（docs/46）"
  local dir ov ref; dir="$(app_dir "$proj")"; ov="$(app_overlay "$proj" "")"; ref="$(app_image_ref "$ov")"
  case "$sub" in
    build)
      [[ -f "$dir/Dockerfile" ]] || die "$proj 没有 Dockerfile（$dir）"
      command -v docker >/dev/null || die "image build 要 docker。没有 docker 的机器上：在别的机器 build、save，再拷过来 import --tar"
      local platform="" i
      for ((i=1; i<${#pos[@]}; i++)); do
        case "${pos[$i]}" in --platform) platform="${pos[$((i+1))]:-}"; i=$((i+1)) ;; --platform=*) platform="${pos[$i]#*=}" ;; *) die "不认识的参数：${pos[$i]}" ;; esac
      done
      local rev; rev="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
      [[ -z "$(git -C "$ROOT" status --porcelain -- "$dir" 2>/dev/null)" ]] || rev="$rev-dirty"
      if docker image inspect "$ref" >/dev/null 2>&1; then
        warn "本机已经有 $ref，会被覆盖。改了代码要先把 $(basename "$ov") 的 newTag 加一，否则节点上不会换新镜像（IfNotPresent）"
      fi
      local args=(build -t "$ref" --label "dev.qpjoy.ladder2.revision=$rev")
      [[ -n "$platform" ]] && args+=(--platform "$platform")
      [[ -n "${NPM_REGISTRY:-}" ]] && args+=(--build-arg "NPM_REGISTRY=$NPM_REGISTRY")
      if [[ -n "${PROXY:-}" ]]; then
        # 构建容器用宿主机网络，才连得上 127.0.0.1 上的代理（docs/31）
        args+=(--network host --build-arg "HTTP_PROXY=$PROXY" --build-arg "HTTPS_PROXY=$PROXY"
               --build-arg "http_proxy=$PROXY" --build-arg "https_proxy=$PROXY" --build-arg "NO_PROXY=localhost,127.0.0.1")
      fi
      echo "▶ 构建 $ref（$dir，修订 $rev${platform:+，平台 $platform}）"
      docker "${args[@]}" "$dir"
      ok "$ref"
      echo "${D}下一步：在每个节点上 sudo ./scripts/manage.sh image import $proj --context <名字>${O}" ;;
    save)
      local out="" i
      for ((i=1; i<${#pos[@]}; i++)); do
        case "${pos[$i]}" in --out) out="${pos[$((i+1))]:-}"; i=$((i+1)) ;; --out=*) out="${pos[$i]#*=}" ;; *) die "不认识的参数：${pos[$i]}" ;; esac
      done
      [[ -n "$out" ]] || die "用法：image save $proj --out <文件.tar>"
      docker image inspect "$ref" >/dev/null 2>&1 || die "本机没有 $ref，先 image build $proj"
      docker save -o "$out" "$ref"
      ok "$ref → $out（拷到节点上：sudo ./scripts/manage.sh image import $proj --tar $out --context <名字>）" ;;
    import)
      local ctx tarf="" i; ctx="$(need_context "$@")"
      for ((i=1; i<${#pos[@]}; i++)); do
        case "${pos[$i]}" in --tar) tarf="${pos[$((i+1))]:-}"; i=$((i+1)) ;; --tar=*) tarf="${pos[$i]#*=}" ;; *) die "不认识的参数：${pos[$i]}" ;; esac
      done
      [[ $EUID -eq 0 ]] || die "导入 containerd 要 root：sudo ./scripts/manage.sh image import $proj --context $ctx"
      command -v ctr >/dev/null || die "本机没有 ctr（containerd）。image import 要在集群的节点上运行"
      # 和 cluster 阶段一样用短主机名（40-cluster.sh 把 hostname -s 写成节点名）
      local me; me="$(hostname -s | tr '[:upper:]' '[:lower:]')"
      kubectl --context "$ctx" --request-timeout=10s get node "$me" >/dev/null 2>&1 \
        || die "本机（$me）不是集群 $ctx 的节点。镜像要导入到会运行它的那台机器上，每个节点各跑一次"
      if [[ -n "$tarf" ]]; then
        [[ -f "$tarf" ]] || die "找不到 $tarf"
        echo "▶ 导入 $tarf 到 containerd（k8s.io）"
        ctr -n k8s.io images import "$tarf"
      else
        command -v docker >/dev/null || die "本机没有 docker：用 --tar 导入别处 image save 出来的文件"
        docker image inspect "$ref" >/dev/null 2>&1 || die "本机 docker 里没有 $ref，先 image build $proj"
        echo "▶ 把 docker 里的 $ref 导入 containerd（k8s.io）"
        docker save "$ref" | ctr -n k8s.io images import -
      fi
      if ctr -n k8s.io images ls -q | grep -qxF "$ref"; then ok "节点 $me 上有 $ref 了"
      else bad "导入后在 containerd 里找不到 $ref（tar 里的镜像名对不上 overlay 的 images:？）"; exit 1; fi ;;
    list)
      echo "${B}overlay 要的${O}  $ref"
      if command -v docker >/dev/null; then
        echo "${B}本机 docker${O}"
        docker image ls "${ref%:*}" --format '  {{.Repository}}:{{.Tag}}  {{.CreatedSince}}  {{.Size}}' 2>/dev/null || echo "  UNKNOWN"
      fi
      if command -v ctr >/dev/null; then
        echo "${B}本机 containerd（k8s.io）${O}"
        if [[ $EUID -eq 0 ]]; then ctr -n k8s.io images ls -q | grep -F "${ref%:*}" | sed 's/^/  /' || echo "  （没有）"
        else echo "  UNKNOWN：要 root 才能看（sudo）"; fi
      fi ;;
    *) die "用法：image build <项目> [--platform linux/amd64] | save <项目> --out <文件> | import <项目> [--tar <文件>] --context <名字> | list <项目>" ;;
  esac
}

# ---------- secret ----------

secret_from_dir() { # 从参数里取 --from，检查它不在本工程目录里
  local from=""
  while (( $# )); do case "$1" in --from) from="${2:-}"; shift 2 || true ;; --from=*) from="${1#*=}"; shift ;; *) shift ;; esac; done
  [[ -n "$from" ]] || die "必须带 --from <目录>：每个 Secret 一个子目录，每个键一个文件（例如 /var/lib/ladder2/secrets/<项目>/）"
  [[ -d "$from" ]] || die "找不到目录：$from"
  from="$(cd "$from" && pwd -P)"
  local root; root="$(cd "$ROOT" && pwd -P)"
  [[ "$from" != "$root" && "$from" != "$root"/* ]] || die "凭据目录不能放在本工程里（$from）。Git 里不放密码、token、私钥（CLAUDE.md）"
  echo "$from"
}

secret_mode_ok() { # 目录和文件不能给组或其他人读
  local p="$1" perm
  perm="$(stat -c '%a' "$p" 2>/dev/null || stat -f '%Lp' "$p")"
  (( (8#$perm & 8#077) == 0 ))
}

cmd_secret() {
  local sub="${1:-}"; shift || true
  local pos=() a
  while IFS= read -r a; do pos+=("$a"); done < <(app_positional "$@")
  local proj="${pos[0]:-}"
  [[ -n "$proj" ]] || die "用法：secret plan|apply <项目> --from <目录> [--context <名字>]（docs/46）"
  local dir; dir="$(app_dir "$proj")"
  [[ -f "$dir/deploy/secrets.list" ]] || die "$proj 没有 deploy/secrets.list"
  local from; from="$(secret_from_dir "$@")"
  local ov ns; ov="$(app_overlay "$proj" "")"; ns="$(app_namespace "$ov")"
  local name keys need k f d rc=0 ctx=""
  case "$sub" in
    plan)
      # --context 可选：给了就同时看集群里有没有
      if printf '%s\n' "$@" | grep -q -- '--context'; then ctx="$(need_context "$@")"; fi
      secret_mode_ok "$from" || warn "$from 组或其他人能读，建议 chmod 700"
      echo "${B}$proj${O}  命名空间 $ns  凭据目录 $from${ctx:+  集群 $ctx}"
      printf "  %-32s %-4s %-26s %s\n" 名字 要求 本地 集群
      while IFS=$'\t' read -r name keys need; do
        d="$from/$name"; local here="" there="-"
        if [[ ! -d "$d" ]]; then here="没有"
        elif [[ "$keys" == "*" ]]; then here="$(find "$d" -maxdepth 1 -type f | wc -l | tr -d ' ') 个键"
        else
          local miss=()
          IFS=',' read -r -a kl <<<"$keys"
          for k in "${kl[@]}"; do [[ -f "$d/$k" ]] || miss+=("$k"); done
          if (( ${#miss[@]} )); then here="缺 ${miss[*]}"; else here="齐（${#kl[@]} 个键）"; fi
        fi
        [[ -d "$d" ]] && ! secret_mode_ok "$d" && here="$here，权限太宽"
        if [[ -n "$ctx" ]]; then
          if secret_exists "$ctx" "$ns" "$name"; then there="有"; else case $? in 1) there="没有" ;; *) there="UNKNOWN"; rc=2 ;; esac; fi
        fi
        if [[ "$need" == 必需 && "$here" != 齐* && "$here" != *个键* && "$there" != 有 ]]; then rc=1; fi
        printf "  %-32s %-4s %-26s %s\n" "$name" "$need" "$here" "$there"
      done < <(secrets_list "$dir")
      (( rc != 1 )) || echo "${R}有必需的 Secret 本地和集群里都没有。${O}格式：$from/<名字>/<键>，一个键一个文件，内容就是值"
      return $rc ;;
    apply)
      ctx="$(need_context "$@")"
      if ! kubectl --context "$ctx" get namespace "$ns" >/dev/null 2>&1; then
        [[ -f "$dir/deploy/k8s/platform/namespace.yaml" ]] || die "集群里没有命名空间 $ns"
        echo "▶ 先建命名空间 $ns（$dir/deploy/k8s/platform/namespace.yaml）"
        kubectl --context "$ctx" apply -f "$dir/deploy/k8s/platform/namespace.yaml"
      fi
      local n=0
      while IFS=$'\t' read -r name keys need; do
        d="$from/$name"
        if [[ ! -d "$d" ]]; then
          [[ "$need" == 必需 ]] && ! secret_exists "$ctx" "$ns" "$name" && { bad "$name：必需，本地和集群里都没有"; rc=1; }
          continue
        fi
        secret_mode_ok "$d" || { bad "$d 组或其他人能读，先 chmod -R go-rwx $from"; rc=1; continue; }
        local args=()
        if [[ "$keys" == "*" ]]; then
          for f in "$d"/*; do [[ -f "$f" ]] && args+=(--from-file="$(basename "$f")=$f"); done
        else
          IFS=',' read -r -a kl <<<"$keys"
          for k in "${kl[@]}"; do
            if [[ -f "$d/$k" ]]; then args+=(--from-file="$k=$d/$k")
            elif [[ "$need" == 必需 ]]; then bad "$name：缺键 $k（$d/$k）"; rc=1; args=(); break; fi
          done
        fi
        (( ${#args[@]} )) || continue
        # 值只经过管道，不打印、不落盘
        kubectl create secret generic "$name" -n "$ns" "${args[@]}" --dry-run=client -o yaml \
          | kubectl --context "$ctx" apply -f - >/dev/null
        echo "  ✎ $name（${#args[@]} 个键）"; n=$((n+1))
      done < <(secrets_list "$dir")
      echo "${D}更新了 $n 个 Secret。已经在跑的 Pod 不会自己读新值：kubectl --context $ctx -n $ns rollout restart deployment/<名字>${O}"
      return $rc ;;
    *) die "用法：secret plan|apply <项目> --from <目录> [--context <名字>]" ;;
  esac
}

# ---------- check ----------

check_launcher_consistency() { # architecture/mx-launcher 里要一致的几处（docs/46、docs/47），manage.sh check 调用
  local s2ip="$1" d="$ROOT/architecture/mx-launcher"
  [[ -d "$d" ]] || return 0
  echo "${B}mx-launcher（architecture/）${O}"
  local cfg="$d/deploy/k8s/base/config.env" ov="$d/deploy/k8s/overlays/ladder2" ref img k v off=1
  cfgv() { awk -F= -v k="$1" '$1==k{print substr($0, length(k)+2)}' "$cfg"; }
  ref="$(app_image_ref "$ov")"; img="$(cfgv MX_INTERNAL_HOST_RUNNER_IMAGE)"
  if [[ "$img" == "$ref" ]]; then ok "config.env 的 host-runner 镜像和 overlay 一致（$ref）"
  else bad "config.env 的 MX_INTERNAL_HOST_RUNNER_IMAGE（$img）和 overlay 的 images:（$ref）不一致"; fi
  if [[ "$ref" == localhost/* || "${ref%%/*}" == *.* || "${ref%%/*}" == *:* ]]; then ok "镜像名带仓库地址，缺镜像时不会去 Docker Hub 拉同名的"
  else bad "镜像名 $ref 没有仓库地址：节点上没有时会去 Docker Hub 拉同名镜像"; fi
  for k in MX_HTTP_TRUST_PROXY_CIDRS GATEWAY_TRUSTED_PROXY_CIDRS; do
    v="$(cfgv "$k")"
    # 只信 Pod 网段：s2 的地址会变，不写进 Launcher 的配置；客户端地址由网关按 trustedAddresses 认（docs/50）
    if [[ "$v" == "$POD_CIDR" ]]; then ok "$k 只信 Pod 网段 $POD_CIDR（客户端地址由网关认，不依赖 s2 的地址）"
    else bad "config.env 的 $k（$v）应该只写 Pod 网段 $POD_CIDR：s2 的地址会变，不要写进这里（docs/50）"; fi
  done
  # service peer（Launcher 的 Internal 角色地址）在三处要一样
  local peer dnsip corefile="$d/deploy/k8s/bootstrap/coredns-config.yaml" gw="$d/deploy/k8s/bootstrap/gateway-config.yaml"
  peer="$(cfgv MX_PUBLIC_BASE_URL | sed -E 's#^https?://([^:/]+).*#\1#')"
  dnsip="$(awk '/externalIPs:/{getline; gsub(/[- ]/,""); print; exit}' "$d/deploy/k8s/dns/coredns.yaml")"
  if [[ -n "$peer" && "$peer" == "$dnsip" ]] && grep -qF "$peer internal.mx gateway.internal.mx" "$corefile"; then
    ok "service peer 地址一致：MX_PUBLIC_BASE_URL、分流 DNS 的 externalIPs、初始 Corefile 都是 $peer"
  else bad "service peer 地址对不上：MX_PUBLIC_BASE_URL=$peer、dns/coredns.yaml externalIPs=$dnsip；改完跑 architecture/mx-launcher/scripts/manage.sh bootstrap-render"; fi
  if grep -qF "trusted_proxies static $(cfgv GATEWAY_TRUSTED_PROXY_CIDRS | tr ',' ' ')" "$gw" && grep -qF "proxy_pass $(cfgv GATEWAY_HOST_NGINX_INTERNAL_API_UPSTREAM);" "$gw"; then
    ok "bootstrap 的应用网关配置是按当前 config.env 生成的"
  else bad "$gw 和 config.env 对不上：跑 architecture/mx-launcher/scripts/manage.sh bootstrap-render"; fi
  # host-runner 的节点选择和 cluster 阶段打的标签是同一个
  local sel; sel="$(cfgv MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR)"
  if [[ -n "$sel" ]] && grep -qF "${sel%%=*}" "$ROOT/scripts/roles/control/40-cluster.sh"; then ok "host-runner 只在 $sel 的节点上跑，cluster 阶段会给 s2 打这个标签"
  else bad "MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR（$sel）和 40-cluster.sh 打的标签对不上"; fi
  # API 不经过应用网关（docs/47）
  if awk '/name: mx-launcher-api/{f=1} f&&/backendRefs/{getline; print; exit}' "$d/deploy/k8s/base/route.yaml" | grep -q 'name: mx-launcher-internal'; then ok "HTTPRoute mx-launcher-api 直接到 Launcher，不经过应用网关"
  else bad "route.yaml 的 mx-launcher-api 后端不是 mx-launcher-internal"; fi
  # site-slot 远程执行可以开（用户 2026-11-22，docs/53），前提是下面的 SSH 白名单有值；密钥导出和 edge-sync 仍然必须关
  for k in SITE_SLOT_DOMESTIC_WG_SECRET_EXPORT_ENABLED SITE_SLOT_SSH_PASSWORD_BOOTSTRAP_ENABLED; do
    v="$(cfgv "$k")"
    [[ "$v" == 0 ]] || { bad "$k=${v:-（没写）}：必须是 0（docs/36、docs/53）"; off=0; }
  done
  if cfgv MX_ENABLED_MODULES | tr ',' ' ' | grep -qw edge-sync; then bad "MX_ENABLED_MODULES 里有 edge-sync：切换前必须去掉（docs/36）"; off=0; fi
  if grep -qE 'name: SITE_SLOT_' "$d/deploy/k8s/base/api.yaml"; then bad "api.yaml 用 env 设了 SITE_SLOT_*，会盖掉 config.env 的 0（L1 的写法）"; off=0; fi
  (( off )) && ok "必须关的开关都关着：WG 密钥导出、用密码装 SSH 公钥、edge-sync（docs/36、docs/53）"
  local remote=0
  for k in SITE_SLOT_RUNNER_REMOTE_EXECUTION_ENABLED SITE_SLOT_WORKER_REMOTE_SSH SITE_SLOT_CONFIRM_REMOTE_EXECUTION; do
    [[ "$(cfgv "$k")" == 1 ]] && remote=1
  done
  if (( remote )) && [[ -z "$(cfgv MX_SITE_SLOT_SSH_ALLOWED_HOSTS)" ]]; then
    bad "site-slot 远程执行开着，但没有 MX_SITE_SLOT_SSH_ALLOWED_HOSTS：能推到任何机器，包括生产的 Domestic（docs/53）"
  elif (( remote )); then ok "site-slot 远程执行开着，只能到白名单里的机器（docs/53）"
  fi
  # Launcher 往外 SSH 的白名单必须有（docs/52）：空着就是 L1 的行为，哪都能连。
  # 写占位、从 inventory 现取（docs/54），不许出现生产 Domestic 的地址
  v="$(cfgv MX_SITE_SLOT_SSH_ALLOWED_HOSTS)"
  local allow
  if [[ -z "$v" ]]; then bad "config.env 没有 MX_SITE_SLOT_SSH_ALLOWED_HOSTS：s2 的 Launcher 能 SSH 到任何机器，包括生产的 Domestic（docs/52）"
  elif ! allow="$(site_ssh_allowlist "$INV_HOSTS" "$v" 2>&1)"; then bad "MX_SITE_SLOT_SSH_ALLOWED_HOSTS（$v）：$(tail -1 <<<"$allow")"
  else
    ok "Launcher 往外 SSH 只能到：$(echo $allow)（config.env 写 $v，地址来自 $(site_field_source domestic02 public_ip)，docs/54）"
    [[ "$v" == *@*@* ]] || warn "MX_SITE_SLOT_SSH_ALLOWED_HOSTS 写死了地址 $v：改成 @DOMESTIC02_PUBLIC_IP@，换地址时只改 inventory（docs/54）"
  fi
  # app apply 先 platform/、再 bootstrap/、最后 overlay：overlay 用到的命名空间要在 platform/ 里建好，否则第一次部署在 bootstrap 那步就停
  local want have miss=""
  # 只看 metadata.namespace（两格缩进），不算 parentRefs 里引用的 gateway 这类别人的命名空间
  want="$( { cat "$d"/deploy/k8s/bootstrap/*.yaml 2>/dev/null; kubectl kustomize "$ov" 2>/dev/null; } | awk '/^  namespace: /{print $2}' | sort -u)"
  have="$(awk '/^kind: Namespace/{n=1;next} n && $1=="name:"{print $2; n=0}' "$d"/deploy/k8s/platform/*.yaml | sort -u)"
  for v in $want; do grep -qx "$v" <<<"$have" || miss+=" $v"; done
  if [[ -z "$miss" ]]; then ok "用到的命名空间（$(echo $want)）都在 platform/ 里先建"
  else bad "platform/ 里没建这些命名空间：$miss（第一次 app deploy 会在 bootstrap 那步失败）"; fi
  local f
  for f in "$d"/deploy/preflight.sh "$d"/deploy/verify.sh "$d"/deploy/once/*.sh; do
    [[ -f "$f" ]] || continue
    bash -n "$f" || bad "$f 语法错误"
  done
  return 0
}

# ---------- k8s capacity（docs/47）：按什么判断新服务放哪台 ----------

k8s_capacity() { # 只读。调度器按 requests 放 Pod，不看实际用量；这里把两样并排列出来
  local ctx="$1" k=(kubectl --context "$1" --request-timeout=15s) n
  local nodes; nodes="$("${k[@]}" get nodes -o name 2>/dev/null)" || { echo "UNKNOWN：连不上集群 $ctx"; return 2; }
  echo "${B}节点：可分配、已被 requests 占用（调度器看的）${O}"
  for n in $nodes; do
    echo "  ${B}${n#node/}${O}  标签：$("${k[@]}" get "$n" -o jsonpath='{.metadata.labels}' | tr ',' '\n' | grep -oE '"(mx\.ladder2|ladder2|node-role\.kubernetes\.io)/[^"]*":"[^"]*"' | tr -d '"' | tr '\n' ' ')"
    echo "    可分配：$("${k[@]}" get "$n" -o jsonpath='cpu {.status.allocatable.cpu}  内存 {.status.allocatable.memory}  临时存储 {.status.allocatable.ephemeral-storage}  Pod {.status.allocatable.pods}')"
    "${k[@]}" describe "$n" | awk '/^Allocated resources:/{f=1;next} f&&/^Events:/{exit} f&&/(cpu|memory|ephemeral-storage) /{gsub(/^ +| +$/,""); gsub(/ +/," "); printf "    已占用（requests limits）：%s\n", $0}'
    local taints; taints="$("${k[@]}" get "$n" -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect} {end}')"
    [[ -n "$taints" ]] && echo "    污点：$taints"
  done
  echo "${B}实际用量${O}（metrics-server）"
  "${k[@]}" top node 2>/dev/null | sed 's/^/  /' || echo "  UNKNOWN：没有 metrics-server（k8s platform metrics-server）"
  echo "${B}本地卷在哪台${O}（local-path 的卷绑死节点，用它的 Pod 只能在那台；数据库就是这样定位的）"
  "${k[@]}" get pv -o jsonpath='{range .items[*]}{.spec.claimRef.namespace}/{.spec.claimRef.name}{"\t"}{.spec.capacity.storage}{"\t"}{.spec.storageClassName}{"\t"}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}' 2>/dev/null \
    | awk -F'\t' 'NF{printf "  %-52s %-7s %-14s %s\n", $1, $2, $3, ($4==""?"（不绑节点）":$4)}' || echo "  UNKNOWN"
  echo "${D}local-path 不看磁盘剩余空间：数据目录 /data/k8s/storage 的余量用 disk record / disk trend 在每台机器上看（docs/20）${O}"
}
