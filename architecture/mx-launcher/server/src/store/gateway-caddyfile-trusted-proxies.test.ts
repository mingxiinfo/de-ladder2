// L2 (de-ladder2 docs/46): the Internal gateway Caddy behind host-nginx and Gateway `internal`.
import assert from 'node:assert/strict';
import test from 'node:test';
import { parseTrustedProxyCidrs } from '../config.js';
import { renderGatewayCaddyfile } from './domain.js';
import type { RuntimeConfig } from '../types.js';

const L1_API_BLOCK = [
  '{',
  '  admin off',
  '  auto_https off',
  '}',
  '',
  ':18090 {',
  '  bind 0.0.0.0',
  '  encode zstd gzip',
  '  header {',
  '    X-MX-Gateway internal-k8s-host-gateway',
  '  }',
  '  @domesticEdge {',
  '    remote_ip 10.88.0.1',
  '    header X-MX-Forwarded-By domestic-edge',
  '  }',
  '  handle @domesticEdge {',
  '    reverse_proxy mx-launcher-internal.mx-internal-shadow.svc.cluster.local:18090 {',
  '      header_up X-Forwarded-For {http.request.header.X-Forwarded-For}',
  '    }',
  '  }',
  '  handle {',
  '    reverse_proxy mx-launcher-internal.mx-internal-shadow.svc.cluster.local:18090 {',
  '      header_up X-Forwarded-For {remote_host}',
  '      header_up -X-MX-Forwarded-By',
  '    }',
  '  }',
  '}',
  ''
].join('\n');

function config(extra: Partial<RuntimeConfig> = {}): RuntimeConfig {
  return { gatewayAppPort: 80, ...extra } as RuntimeConfig;
}

test('without trusted proxies the Caddyfile is the L1 one', () => {
  const caddyfile = renderGatewayCaddyfile(config(), []);
  assert.ok(caddyfile.startsWith(L1_API_BLOCK), 'the :18090 block must stay byte-identical to L1');
  assert.doesNotMatch(caddyfile, /trusted_proxies|client_ip/);
  assert.equal(renderGatewayCaddyfile(config({ gatewayTrustedProxyCidrs: [] }), []), caddyfile);
});

test('behind proxies Caddy trusts only the listed CIDRs and reads X-Forwarded-For right to left', () => {
  const caddyfile = renderGatewayCaddyfile(config({
    gatewayTrustedProxyCidrs: ['192.168.224.0/20', '192.168.1.4/32']
  }), []);
  assert.match(caddyfile, /^ {4}trusted_proxies static 192\.168\.224\.0\/20 192\.168\.1\.4\/32$/m);
  assert.match(caddyfile, /^ {4}trusted_proxies_strict$/m);
  assert.doesNotMatch(caddyfile, /client_ip_headers/, 'X-Forwarded-For is the Caddy default');
  assert.match(caddyfile, /^ {4}client_ip 10\.88\.0\.1$/m);
  assert.doesNotMatch(caddyfile, /remote_ip|\{remote_host\}/);
  assert.match(caddyfile, /header_up X-Forwarded-For \{http\.request\.header\.X-MX-Edge-Forwarded-For\}/);
  assert.match(caddyfile, /header_up X-Forwarded-For \{client_ip\}/);
  assert.equal(caddyfile.match(/header_up -X-MX-Edge-Forwarded-For/g)?.length, 2, 'the copied header never reaches Launcher');
  assert.match(caddyfile, /:8008 \{/, 'app ports are unchanged');
});

test('header names can be overridden', () => {
  const caddyfile = renderGatewayCaddyfile(config({
    gatewayTrustedProxyCidrs: ['10.0.0.0/8'],
    gatewayClientIpHeader: 'X-Client-IP',
    gatewayEdgeForwardedForHeader: 'X-Edge-XFF'
  }), []);
  assert.match(caddyfile, /client_ip_headers X-Client-IP/);
  assert.match(caddyfile, /\{http\.request\.header\.X-Edge-XFF\}/);
});

test('GATEWAY_TRUSTED_PROXY_CIDRS accepts IPv4 CIDRs and refuses anything else', () => {
  assert.deepEqual(parseTrustedProxyCidrs(undefined), []);
  assert.deepEqual(parseTrustedProxyCidrs('  '), []);
  assert.deepEqual(
    parseTrustedProxyCidrs('192.168.224.0/20, 192.168.1.4/32 192.168.224.0/20'),
    ['192.168.224.0/20', '192.168.1.4/32']
  );
  assert.throws(() => parseTrustedProxyCidrs('192.168.1.4'), /not an IPv4 CIDR/);
  assert.throws(() => parseTrustedProxyCidrs('192.168.1.400/32'), /not an IPv4 CIDR/);
  assert.throws(() => parseTrustedProxyCidrs('0.0.0.0/33'), /not an IPv4 CIDR/);
  assert.throws(() => parseTrustedProxyCidrs('private_ranges'), /not an IPv4 CIDR/);
});
