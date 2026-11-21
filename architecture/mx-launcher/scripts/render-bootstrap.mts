// 生成 deploy/k8s/bootstrap/ 里两个"只建一次、之后归 Launcher 改"的 ConfigMap（docs/47）：
//   gateway-config.yaml  mx-internal-shadow/mx-internal-gateway-caddy：nginx.conf（应用网关在用）、Caddyfile（留着）
//   coredns-config.yaml  mx-dns/coredns：Corefile
// 内容用 Launcher 自己的生成函数，参数取 deploy/k8s/base/config.env，没有路由。
// 运行：architecture/mx-launcher/scripts/manage.sh bootstrap-render（要先在 server/ 里 pnpm install）
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderGatewayCaddyfile, renderGatewayNginxConfig } from '../server/src/store/domain.ts';
import { parseTrustedProxyCidrs } from '../server/src/config.ts';

const here = dirname(fileURLToPath(import.meta.url));
const project = resolve(here, '..');
const env = Object.fromEntries(
  readFileSync(resolve(project, 'deploy/k8s/base/config.env'), 'utf8')
    .split('\n')
    .filter((line) => line && !line.startsWith('#') && line.includes('='))
    .map((line) => [line.slice(0, line.indexOf('=')), line.slice(line.indexOf('=') + 1)])
);
const required = (key: string) => {
  const value = env[key];
  if (!value) throw new Error(`config.env 没有 ${key}`);
  return value;
};

const serviceIp = new URL(required('MX_PUBLIC_BASE_URL')).hostname;
const runtime = {
  gatewayAppPort: Number(required('GATEWAY_APP_PORT')),
  gatewayTrustedProxyCidrs: parseTrustedProxyCidrs(env.GATEWAY_TRUSTED_PROXY_CIDRS),
  gatewayHostNginxInternalApiUpstream: env.GATEWAY_HOST_NGINX_INTERNAL_API_UPSTREAM || null
} as never;

const indent = (text: string) => text.replace(/\n$/, '').split('\n').map((line) => (line ? `    ${line}` : '')).join('\n');
const header = (what: string) => [
  `# ${what}`,
  '# 只在集群里还没有时由 ./scripts/manage.sh app apply / app deploy 建一次，之后归 Launcher 运行时改写，不会被覆盖（docs/47）。',
  '# 不要手改：改 deploy/k8s/base/config.env 或 Launcher 的生成函数后，跑 architecture/mx-launcher/scripts/manage.sh bootstrap-render。',
].join('\n');

const gatewayRoutes = JSON.stringify({
  environment: required('MX_ENVIRONMENT'),
  siteId: required('MX_SITE_ID'),
  gatewayPort: Number(required('GATEWAY_APP_PORT')),
  routeCount: 0,
  routes: []
}, null, 2);

writeFileSync(resolve(project, 'deploy/k8s/bootstrap/gateway-config.yaml'), `${header('应用网关 mx-internal-gateway 的初始配置。nginx.conf 给 nginx 用（app-gateway.yaml），Caddyfile 是 Launcher 一起生成的，L2 不用。')}
apiVersion: v1
kind: ConfigMap
metadata:
  name: mx-internal-gateway-caddy
  namespace: mx-internal-shadow
  labels:
    app.kubernetes.io/name: mx-internal-gateway
    app.kubernetes.io/part-of: mx-3ks
    mx.qpjoy.com/component: internal-gateway
    ladder2/project: mx-launcher
data:
  nginx.conf: |
${indent(renderGatewayNginxConfig(runtime, []))}
  Caddyfile: |
${indent(renderGatewayCaddyfile(runtime, []))}
  mx-gateway-routes.json: |
${indent(gatewayRoutes)}
`);

// 照 L1 deploy/k8s/internal-shadow/15-dns-control-target.yaml 的初始 Corefile，Internal 地址换成 config.env 里的。
// Launcher 第一次在 DNS 页面 Apply 时会整份重写。
const corefile = `internal.mx:53 {
  errors
  log
  hosts {
    ${serviceIp} internal.mx gateway.internal.mx dns.internal.mx service-peer.internal.mx
    10.88.0.1 domestic-relay.internal.mx
    fallthrough
  }
  rewrite name exact host-runner.internal.mx mx-internal-host-runner.mx-internal-shadow.svc.cluster.local
  cache 30
  reload
  forward . /etc/resolv.conf
}
corp.mx:53 {
  errors
  log
  cache 30
  reload
  forward . /etc/resolv.conf
}
h2i.mx:53 {
  errors
  log
  cache 30
  reload
  forward . /etc/resolv.conf
}
.:53 {
  errors
  hosts {
    ${serviceIp} h2i.mxinfo-inc.cn
    fallthrough
  }
  cache 30
  reload
  forward . /etc/resolv.conf
}
`;

writeFileSync(resolve(project, 'deploy/k8s/bootstrap/coredns-config.yaml'), `${header('分流 DNS mx-internal-coredns 的初始 Corefile。')}
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: mx-dns
  labels:
    app.kubernetes.io/name: coredns
    app.kubernetes.io/part-of: mx-3ks
    mx.qpjoy.com/component: dns-control
    ladder2/project: mx-launcher
data:
  Corefile: |
${indent(corefile)}
  mx-zone-snapshot.json: "{}"
`);

console.log(`bootstrap 已生成：service peer ${serviceIp}，应用端口 ${env.GATEWAY_APP_PORT}`);
