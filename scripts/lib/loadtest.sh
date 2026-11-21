# 压测（docs/09 的压测步骤、docs/35）。被 scripts/manage.sh source，不单独运行。
#
#   loadtest run <链路> --hop <service|gateway|host-nginx|edge> [--rate 1000] [--duration 2m] [--from cluster|here] [--context 名字]
#   loadtest pg [--rate 1000] [--duration 2m] [--mode select|write] --context <名字>
#   loadtest results
#
# 规矩：不压 s1 和 Launcher 的接口（docs/09）；不在 s1 上发起；边缘 Domestic 和 MX-H2I 共用，压它要人工确认。
# 结果记在本机 $LT_RESULTS，node verify <主机> loadtest 读它。

lt_seconds() { awk -v d="$1" 'BEGIN{ s=0; while (match(d,/[0-9]+[hms]/)) { t=substr(d,RSTART,RLENGTH); n=substr(t,1,length(t)-1)+0; u=substr(t,length(t)); s+= (u=="h")?n*3600:(u=="m")?n*60:n; d=substr(d,RSTART+RLENGTH) } print (s>0?s:60) }'; }

lt_limits() { # lt_limits <层> → "p95 p99"，毫秒。估算的门槛，用 LOADTEST_P95 / LOADTEST_P99 覆盖
  local p95 p99
  case "$1" in
    service)            p95=20;  p99=50 ;;
    gateway|host-nginx) p95=30;  p99=100 ;;
    edge)               p95=300; p99=800 ;;
  esac
  echo "${LOADTEST_P95:-$p95} ${LOADTEST_P99:-$p99}"
}

lt_guard() { # lt_guard <目标地址>
  is_s1_here && die "这台是 s1。不在 s1 上发起压测（会吃 s1 的 CPU 和网卡）。"
  local ip h="${1#*://}"; h="${h%%/*}"; h="${h%%:*}"
  for ip in "$(host_field s1 lan_ip)" "$(host_field s1 wg_ip)" "$(host_field s1 openvpn_ip)"; do
    if [[ -n "$ip" && "$h" == "$ip" ]]; then die "目标 $1 是 s1。不对 s1 和 Launcher 的接口压测（docs/09）。"; fi
  done
  return 0
}

lt_record() { # lt_record <链路> <层> <从哪> <目标速率> <摘要JSON> <通过|没过> <编号>
  mkdir -p "$LT_DIR"; chmod 700 "$LT_DIR"
  local row
  row="$(python3 -c '
import json,sys
d=json.loads(sys.argv[1]) if sys.argv[1] else {}
f=lambda k,n=1: ("%.*f"%(n,d[k])) if isinstance(d.get(k),(int,float)) else "-"
fail="%.3f%%"%(d["failed"]*100) if isinstance(d.get("failed"),(int,float)) else "-"
print("\t".join([f("achieved"),f("p50",2),f("p95",2),f("p99",2),fail,str(d.get("dropped","-"))]))' "$5")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$2" "$3" "$4" "$row" "$6" "$7" >>"$LT_RESULTS"
  local a p50 p95 p99 fail drop
  IFS=$'\t' read -r a p50 p95 p99 fail drop <<<"$row"
  local mark="${G}通过${O}"; [[ "$6" == 通过 ]] || mark="${R}没过${O}"
  printf "  %s / %s（从%s）  目标 %s/s  实际 %s/s  p50 %s  p95 %s  p99 %s ms  错误 %s  丢弃 %s  → %b\n" \
    "$1" "$2" "$([[ "$3" == cluster ]] && echo 集群里 || echo 本机)" "$4" "$a" "$p50" "$p95" "$p99" "$fail" "$drop" "$mark"
}

lt_summary_of() { grep -a '^LADDER2_SUMMARY ' "$1" 2>/dev/null | tail -1 | cut -d' ' -f2-; }

lt_wait_job() { # lt_wait_job <context> <命名空间> <Job> <最多等几秒>：成功返回 0
  local ctx="$1" ns="$2" job="$3" limit="$4" t=0 st
  while (( t < limit )); do
    st="$(kubectl --context "$ctx" -n "$ns" get job "$job" -o jsonpath='{.status.succeeded}:{.status.failed}' 2>/dev/null || true)"
    [[ "$st" == 1:* ]] && return 0
    [[ "$st" == *:1 ]] && return 1
    sleep 5; t=$((t+5))
  done
  echo "  ${Y}!${O} 等了 ${limit} 秒 Job 还没结束" >&2
  return 1
}

lt_http_cluster() { # lt_http_cluster <context> <编号> <目标> <Host> <速率> <时长> <p95> <p99> <日志文件>
  local ctx="$1" id="$2" k=(kubectl --context "$1")
  "${k[@]}" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: loadtest
  labels:
    ladder2/purpose: loadtest
EOF
  "${k[@]}" -n loadtest create configmap k6-http --from-file=http.js="$ROOT/scripts/loadtest/http.js" \
    --dry-run=client -o yaml | "${k[@]}" apply -f - >/dev/null
  "${k[@]}" apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $id
  namespace: loadtest
  labels: { ladder2/purpose: loadtest }
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400     # 一天后 Job 自己清掉；结果已经记在本机
  template:
    metadata:
      labels: { ladder2/purpose: loadtest }
    spec:
      restartPolicy: Never
      containers:
        - name: k6
          image: $K6_IMAGE
          args: ["run", "--quiet", "--no-color", "/scripts/http.js"]
          env:
            - { name: TARGET,   value: "$3" }
            - { name: HOST,     value: "$4" }
            - { name: RATE,     value: "$5" }
            - { name: DURATION, value: "$6" }
            - { name: P95,      value: "$7" }
            - { name: P99,      value: "$8" }
            - { name: RID,      value: "$id" }
          resources:
            requests: { cpu: "2", memory: 512Mi }
            limits: { memory: 2Gi }
          volumeMounts:
            - { name: script, mountPath: /scripts }
      volumes:
        - name: script
          configMap: { name: k6-http }
EOF
  echo "  Job loadtest/$id 已提交，压 $6，结束后取结果"
  local rc=0
  lt_wait_job "$ctx" loadtest "$id" $(( $(lt_seconds "$6") + 300 )) || rc=1
  "${k[@]}" -n loadtest logs "job/$id" >"$9" 2>&1 || true
  return $rc
}

lt_http_here() { # lt_http_here <编号> <目标> <Host> <速率> <时长> <p95> <p99> <日志文件>
  local env=(TARGET="$2" HOST="$3" RATE="$4" DURATION="$5" P95="$6" P99="$7" RID="$1")
  if command -v k6 >/dev/null; then
    env "${env[@]}" k6 run --quiet --no-color "$ROOT/scripts/loadtest/http.js" >"$8" 2>&1
  elif command -v docker >/dev/null; then
    local e a=()
    for e in "${env[@]}"; do a+=(-e "$e"); done
    # 不新建 Docker 网络（CLAUDE.md），用默认网络
    docker run --rm "${a[@]}" -v "$ROOT/scripts/loadtest:/scripts:ro" "$K6_IMAGE" run --quiet --no-color /scripts/http.js >"$8" 2>&1
  else
    die "本机没有 k6，也没有 docker。装 k6，或者用 --from cluster。"
  fi
}

lt_run() {
  local route="${1:-}"; shift || true
  [[ -n "$route" && "$route" != -* ]] || die "用法：loadtest run <链路> --hop <service|gateway|host-nginx|edge> [--rate 1000] [--duration 2m] [--from cluster|here] --context <名字>"
  local hop="" rate="" dur="${LOADTEST_DURATION:-2m}" from="" args=("$@")
  while (( $# )); do
    case "$1" in
      --hop) hop="${2:-}"; shift 2 ;;
      --rate) rate="${2:-}"; shift 2 ;;
      --duration) dur="${2:-}"; shift 2 ;;
      --from) from="${2:-}"; shift 2 ;;
      --context) shift 2 ;;
      --context=*) shift ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [[ -n "$(probe_field "$route" path)" ]] || die "inventory/probes.yaml 里没有链路 $route。probe list 看有哪些。"
  case "$hop" in service|gateway|host-nginx|edge) ;; *) die "--hop 只能是 service、gateway、host-nginx、edge" ;; esac
  [[ -n "$from" ]] || { [[ "$hop" == edge ]] && from=here || from=cluster; }
  [[ "$from" == cluster || "$from" == here ]] || die "--from 只能是 cluster 或 here"
  [[ "$hop" != edge || "$from" == here ]] || die "边缘要从集群外面压：--from here"
  [[ -n "$rate" ]] || { [[ "$hop" == edge ]] && rate=100 || rate=1000; }
  [[ "$rate" =~ ^[0-9]+$ ]] || die "--rate 要是整数"

  local field
  case "$hop" in
    service) field=$([[ "$from" == cluster ]] && echo in_cluster || echo service) ;;
    host-nginx) field=host_nginx ;;
    *) field="$hop" ;;
  esac
  local base path host target
  base="$(probe_field "$route" "$field")"; path="$(probe_field "$route" path)"; host="$(probe_field "$route" host)"
  [[ -n "$base" && "$base" != *待确认* ]] || die "链路 $route 的 $field 没有登记（inventory/probes.yaml）"
  target="$base$path"
  lt_guard "$target"
  local ctx=""
  [[ "$from" == here ]] || ctx="$(need_context "${args[@]}")"

  if [[ "$hop" == edge ]]; then
    echo "${Y}边缘 Domestic 只有 2 vCPU、峰值 100 Mbps，和 MX-H2I 的用户共用。压它会影响 H2I 的登录和联网。${O}"
    echo "只在没人用的时段压，速率从 100 起（现在 $rate/s，$dur）。"
    confirm "确定现在压边缘？"
  fi

  local p95 p99 id log rc=0
  read -r p95 p99 <<<"$(lt_limits "$hop")"
  id="k6-$route-$hop-$(date +%Y%m%d%H%M%S)"; id="${id:0:63}"
  mkdir -p "$LT_DIR"; chmod 700 "$LT_DIR"; log="$LT_DIR/$id.log"
  echo "${B}$route / $hop${O}  $target（Host: $host）  $rate/s × $dur  门槛 p95<${p95}ms p99<${p99}ms 错误<0.1% 达到 99% 速率（估算，docs/35）"
  if [[ "$from" == cluster ]]; then
    lt_http_cluster "$ctx" "$id" "$target" "$host" "$rate" "$dur" "$p95" "$p99" "$log" || rc=1
  else
    lt_http_here "$id" "$target" "$host" "$rate" "$dur" "$p95" "$p99" "$log" || rc=1
  fi
  local sum; sum="$(lt_summary_of "$log")"
  if [[ -z "$sum" ]]; then
    echo "  ${R}没有拿到结果${O}，日志最后 20 行（$log）："; tail -20 "$log" 2>/dev/null | sed 's/^/    /'
    lt_record "$route" "$hop" "$from" "$rate" "" 没过 "$id"; return 1
  fi
  if (( rc == 0 )); then lt_record "$route" "$hop" "$from" "$rate" "$sum" 通过 "$id"
  else lt_record "$route" "$hop" "$from" "$rate" "$sum" 没过 "$id"; return 1; fi
}

lt_pg() {
  local rate="" dur="${LOADTEST_DURATION:-2m}" mode=select args=("$@")
  while (( $# )); do
    case "$1" in
      --rate) rate="${2:-}"; shift 2 ;;
      --duration) dur="${2:-}"; shift 2 ;;
      --mode) mode="${2:-}"; shift 2 ;;
      --context) shift 2 ;;
      --context=*) shift ;;
      *) die "未知参数：$1" ;;
    esac
  done
  rate="${rate:-1000}"
  [[ "$mode" == select || "$mode" == write ]] || die "--mode 只能是 select 或 write"
  is_s1_here && die "这台是 s1。不在 s1 上发起压测。"
  local ctx; ctx="$(need_context "${args[@]}")"
  local k=(kubectl --context "$ctx" -n data) prim image owner id log secs flag
  prim="$("${k[@]}" get cluster pg-common -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
  [[ -n "$prim" ]] || die "UNKNOWN：找不到 pg-common 的主库（先做阶段 postgres）"
  image="$("${k[@]}" get pod "$prim" -o jsonpath='{.spec.containers[?(@.name=="postgres")].image}')"
  owner="$("${k[@]}" get secret pg-common-app -o jsonpath='{.data.username}' | base64 --decode)"
  # 压测用单独的库 ladder2_loadtest，不碰业务库。只建不删。
  if [[ "$("${k[@]}" exec "$prim" -c postgres -- psql -U postgres -tAc "select 1 from pg_database where datname='ladder2_loadtest'")" != 1 ]]; then
    "${k[@]}" exec "$prim" -c postgres -- psql -U postgres -c "create database ladder2_loadtest owner \"$owner\"" >/dev/null
    echo "  建了压测用的库 ladder2_loadtest（属主 $owner）"
  fi
  secs="$(lt_seconds "$dur")"; flag=$([[ "$mode" == select ]] && echo -S || echo -N)
  id="pgbench-$mode-$(date +%Y%m%d%H%M%S)"; mkdir -p "$LT_DIR"; chmod 700 "$LT_DIR"; log="$LT_DIR/$id.log"
  echo "${B}pg-common / pg${O}（$mode）  pg-common-rw  $rate 事务/s × $dur  门槛：达到 99% 速率、没有失败、超过 50 ms 的不到 1%（估算，docs/35）"
  "${k[@]}" apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $id
  namespace: data
  labels: { ladder2/purpose: loadtest }
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels: { ladder2/purpose: loadtest }
    spec:
      restartPolicy: Never
      containers:
        - name: pgbench
          image: $image
          command: ["bash", "-c"]
          args:
            - |
              set -e
              if [ -z "\$(psql -tAc "select to_regclass('pgbench_accounts')")" ]; then
                echo "初始化 pgbench 的表（规模 50，约 750 MB）"; pgbench -i -s 50 -q
              fi
              pgbench -n $flag -R $rate -T $secs -c 32 -j 8 -L 50 --progress=30
          env:
            - { name: PGHOST, value: pg-common-rw }
            - { name: PGDATABASE, value: ladder2_loadtest }
            - name: PGUSER
              valueFrom: { secretKeyRef: { name: pg-common-app, key: username } }
            - name: PGPASSWORD
              valueFrom: { secretKeyRef: { name: pg-common-app, key: password } }
          resources:
            requests: { cpu: "4", memory: 512Mi }
            limits: { memory: 2Gi }
EOF
  local rc=0
  lt_wait_job "$ctx" data "$id" $((secs + 900)) || rc=1
  "${k[@]}" logs "job/$id" >"$log" 2>&1 || true
  local sum
  sum="$(python3 -c '
import re,sys,json
t=open(sys.argv[1],errors="replace").read(); rate=float(sys.argv[2])
g=lambda p: (lambda m: float(m.group(1)) if m else None)(re.search(p,t))
tps=g(r"tps = ([0-9.]+)"); lat=g(r"latency average = ([0-9.]+) ms")
proc=g(r"actually processed: ([0-9]+)"); failed=g(r"number of failed transactions: ([0-9]+)") or 0
late=g(r"above the [0-9.]+ ms latency limit: ([0-9]+)") or 0; skipped=g(r"transactions skipped: ([0-9]+)") or 0
ok = tps is not None and tps >= rate*0.99 and failed == 0 and proc and (late+skipped) <= proc*0.01
print(json.dumps({"achieved":tps,"p50":lat,"failed":(failed/proc if proc else None),"dropped":int(late+skipped),"ok":bool(ok)}))' "$log" "$rate" 2>/dev/null || true)"
  if [[ -z "$sum" ]]; then echo "  ${R}没有拿到结果${O}（$log）"; tail -20 "$log" 2>/dev/null | sed 's/^/    /'; return 1; fi
  echo "    ${D}pg 的 p50 一列是平均延迟；丢弃一列是超过 50 ms 和被跳过的事务数${O}"
  if (( rc == 0 )) && [[ "$sum" == *'"ok": true'* ]]; then lt_record pg-common pg cluster "$rate" "$sum" 通过 "$id"
  else lt_record pg-common pg cluster "$rate" "$sum" 没过 "$id"; return 1; fi
}

lt_results() {
  [[ -s "$LT_RESULTS" ]] || die "这台机器上还没有压测记录（$LT_RESULTS）"
  printf "${B}%-16s %-16s %-11s %-7s %6s %9s %7s %7s %7s %8s %6s %s${O}\n" 时间 链路 层 从哪 目标 实际 p50 p95 p99 错误 丢弃 结果
  awk -F'\t' '{ last[$2"\t"$3]=$0 } END{ for (k in last) print last[k] }' "$LT_RESULTS" | sort -t$'\t' -k2,3 \
    | awk -F'\t' '{ printf "%-16s %-16s %-11s %-7s %6s %9s %7s %7s %7s %8s %6s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12 }'
  echo "${D}每条链路每一层只显示最近一次。全部记录：$LT_RESULTS；每次的日志在同一目录。延迟单位毫秒。${O}"
}

cmd_loadtest() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    run) lt_run "$@" ;;
    pg) lt_pg "$@" ;;
    results) lt_results ;;
    *) die "用法：loadtest run <链路> --hop <service|gateway|host-nginx|edge> [--rate N] [--duration 2m] [--from cluster|here] --context <名字> | loadtest pg --context <名字> [--mode select|write] | loadtest results" ;;
  esac
}
