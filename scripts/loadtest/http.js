// HTTP 压测脚本（docs/09 的压测步骤、docs/35）。由 ./scripts/manage.sh loadtest run 调用，参数全从环境变量来。
// 固定到达速率：不管响应快慢，每秒都发 RATE 个请求。后端跟不上时请求会被丢弃（dropped_iterations），算作没扛住。
import http from 'k6/http';
import { check } from 'k6';

const TARGET = __ENV.TARGET;                    // 完整地址，例如 http://<s2 地址>:30080/healthz
const HOST = __ENV.HOST || '';                  // Host 头，内网各层靠它选路由
const RATE = parseInt(__ENV.RATE || '1000', 10);
const DURATION = __ENV.DURATION || '2m';
const P95 = __ENV.P95 || '50';                  // 毫秒
const P99 = __ENV.P99 || '100';
const RID = __ENV.RID || 'loadtest';            // 请求编号前缀，各层访问日志里用它找到这次压测

function seconds(d) {
  let s = 0;
  for (const [, n, u] of d.matchAll(/(\d+)(h|m|s)/g)) s += parseInt(n, 10) * ({ h: 3600, m: 60, s: 1 })[u];
  return s || 60;
}
// 允许丢掉 1% 的请求（达到目标速率的 99% 算扛住）
const DROP_LIMIT = Math.ceil(RATE * seconds(DURATION) * 0.01);

export const options = {
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: Math.max(50, Math.ceil(RATE / 5)),
      maxVUs: Math.max(200, RATE * 2),
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.001'],            // 错误率低于 0.1%
    http_req_duration: [`p(95)<${P95}`, `p(99)<${P99}`],
    dropped_iterations: [`count<${DROP_LIMIT}`],
  },
};

const params = { headers: { 'X-Request-Id': RID }, timeout: '10s' };
if (HOST) params.headers.Host = HOST;

export default function () {
  const res = http.get(TARGET, params);
  check(res, { 'status 200': (r) => r.status === 200 });
}

// 只输出一行机器可读的结果，manage.sh 解析它。是否通过以 k6 的退出码为准（阈值没过退出码是 99）。
export function handleSummary(data) {
  const m = data.metrics;
  const v = (name) => (m[name] ? m[name].values : {});
  const d = v('http_req_duration');
  const out = {
    target: TARGET, host: HOST, rate: RATE, duration: DURATION, p95_limit: Number(P95), p99_limit: Number(P99),
    reqs: v('http_reqs').count || 0,
    achieved: v('http_reqs').rate || 0,
    p50: d.med, p95: d['p(95)'], p99: d['p(99)'], max: d.max,
    failed: v('http_req_failed').rate === undefined ? null : v('http_req_failed').rate,
    dropped: v('dropped_iterations').count || 0,
  };
  return { stdout: 'LADDER2_SUMMARY ' + JSON.stringify(out) + '\n' };
}
