// L2 (de-ladder2 docs/47): trust proxy by address range, host-runner node selector.
import assert from 'node:assert/strict';
import test from 'node:test';
import { createRequire } from 'node:module';
import { httpTrustProxySetting } from './trust-proxy.js';
import { parseNodeSelector } from './host-runner-node-selector.js';
import { internalServicePeerHostRunnerK8sObjects } from '../modules/admin/admin.controller.js';

test('trust proxy: CIDRs win over hops; nothing set keeps Express default', () => {
  assert.equal(httpTrustProxySetting({}), null);
  assert.equal(httpTrustProxySetting({ MX_HTTP_TRUST_PROXY_HOPS: '1' }), 1);
  assert.equal(httpTrustProxySetting({ MX_HTTP_TRUST_PROXY_HOPS: 'x' }), null);
  assert.deepEqual(
    httpTrustProxySetting({ MX_HTTP_TRUST_PROXY_HOPS: '1', MX_HTTP_TRUST_PROXY_CIDRS: '192.168.224.0/20,192.168.1.4/32' }),
    ['192.168.224.0/20', '192.168.1.4/32']
  );
  assert.throws(() => httpTrustProxySetting({ MX_HTTP_TRUST_PROXY_CIDRS: '192.168.1.4' }), /not an IPv4 CIDR/);
});

// Express computes req.ip with proxy-addr. Load the copy Express itself uses (it is not a direct
// dependency), then check the L2 chain host-nginx → gateway Pod → Launcher.
const fromNest = createRequire(createRequire(import.meta.url).resolve('@nestjs/platform-express'));
const proxyaddr = createRequire(fromNest.resolve('express'))('proxy-addr') as {
  (req: unknown, trust: unknown): string;
  compile(value: string[]): unknown;
};
function clientIp(remote: string, xff: string, trust: string[]): string {
  const req = { socket: { remoteAddress: remote }, connection: { remoteAddress: remote }, headers: { 'x-forwarded-for': xff } };
  return proxyaddr(req as never, proxyaddr.compile(trust));
}

test('req.ip behind host-nginx and the gateway is the client, whatever the gateway appends', () => {
  const trust = ['192.168.224.0/20', '192.168.1.4/32'];
  const gatewayPod = '::ffff:192.168.224.17';
  // host-nginx overwrote XFF with the H2I client; the gateway appended the rewritten client
  assert.equal(clientIp(gatewayPod, '10.89.0.23, 10.89.0.23', trust), '10.89.0.23');
  // the gateway appended host-nginx's own address instead
  assert.equal(clientIp(gatewayPod, '10.89.0.23, 192.168.1.4', trust), '10.89.0.23');
  // Domestic edge: host-nginx kept the edge's X-Forwarded-For (the public user)
  assert.equal(clientIp(gatewayPod, '203.0.113.7, 192.168.224.1', trust), '203.0.113.7');
  // a direct connection that bypasses the proxies is its own client, XFF ignored
  assert.equal(clientIp('10.89.0.99', '1.2.3.4', trust), '10.89.0.99');
});

test('host-runner node selector parses key=value labels and refuses junk', () => {
  assert.equal(parseNodeSelector(undefined), null);
  assert.equal(parseNodeSelector(' '), null);
  assert.deepEqual(parseNodeSelector('mx.ladder2/site-peer=true'), { 'mx.ladder2/site-peer': 'true' });
  assert.deepEqual(parseNodeSelector('a=1, kubernetes.io/os=linux'), { a: '1', 'kubernetes.io/os': 'linux' });
  assert.throws(() => parseNodeSelector('site-peer'), /key=value/);
  assert.throws(() => parseNodeSelector('=true'), /key=value/);
  assert.throws(() => parseNodeSelector('a=b c'), /key=value/, 'space splits into a second, invalid item');
});

test('Launcher-created host-runner DaemonSet gets the node selector only when configured', () => {
  const previous = process.env.MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR;
  try {
    delete process.env.MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR;
    const plain = internalServicePeerHostRunnerK8sObjects('mx-internal-shadow', 'mx-internal-host-runner', 19190);
    const plainSpec = (plain[1] as any).spec.template.spec;
    assert.equal(plainSpec.nodeSelector, undefined, 'L1 behaviour unchanged');
    assert.equal(plainSpec.hostNetwork, true);
    process.env.MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR = 'mx.ladder2/site-peer=true';
    const pinned = internalServicePeerHostRunnerK8sObjects('mx-internal-shadow', 'mx-internal-host-runner', 19190);
    assert.deepEqual((pinned[1] as any).spec.template.spec.nodeSelector, { 'mx.ladder2/site-peer': 'true' });
  } finally {
    if (previous === undefined) delete process.env.MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR;
    else process.env.MX_INTERNAL_HOST_RUNNER_NODE_SELECTOR = previous;
  }
});
