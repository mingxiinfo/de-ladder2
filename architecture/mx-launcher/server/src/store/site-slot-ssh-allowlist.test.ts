// L2 (de-ladder2 docs/52): MX_SITE_SLOT_SSH_ALLOWED_HOSTS keeps s2's Launcher from SSHing anywhere
// but its test relay (domestic02). Empty keeps the L1 behaviour.
import 'reflect-metadata';
import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../config.js';
import { MemoryStore } from './memory.js';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { assertSiteSlotSshHostAllowed, siteSlotSshProfileAllowed } from './domain.js';

const relay = '203.0.113.10';
const production = '198.51.100.20';

test('no allowlist: any host, as in L1', () => {
  const config = { ...loadConfig(), siteSlotSshAllowedHosts: [] };
  const store = new MemoryStore(config);
  const profile = store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic-main', host: production });
  assert.equal(profile.host, production);
  assert.equal(store.getSiteSlotSshProfile(profile.profileId)?.host, production);
});

test('allowlist: only listed hosts can get a profile', () => {
  const config = { ...loadConfig(), siteSlotSshAllowedHosts: [relay] };
  const store = new MemoryStore(config);
  assert.equal(store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic02', host: relay }).host, relay);
  assert.throws(
    () => store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic-main', host: production }),
    /not in MX_SITE_SLOT_SSH_ALLOWED_HOSTS/,
  );
  assert.doesNotThrow(() => assertSiteSlotSshHostAllowed(config, relay.toUpperCase(), null));
});

test('allowlist: the ssh_config the SSH profile bootstrap writes is accepted only when it stays on listed hosts', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ssh-allow-'));
  const write = (name: string, text: string) => { const f = join(dir, name); writeFileSync(f, text); return f; };
  const config = { ...loadConfig(), siteSlotSshAllowedHosts: [relay] };
  const store = new MemoryStore(config);
  // the shape ssh-profile-bootstrap.ts writes
  const good = write('config.domestic02', `Host domestic02\n  HostName ${relay}\n  User root\n  Port 22\n  StrictHostKeyChecking yes\n`);
  assert.equal(store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic02', host: relay, sshConfigFile: good }).sshConfigFile, good);
  for (const [name, text, why] of [
    ['other', `Host domestic02\n  HostName ${production}\n`, /HostName .* outside/],
    ['jump', `Host domestic02\n  HostName ${relay}\n  ProxyJump root@${production}\n`, /ProxyJump/],
    ['command', `Host domestic02\n  HostName ${relay}\n  ProxyCommand ssh -W %h:%p ${production}\n`, /ProxyCommand/],
    ['include', `Include /etc/ssh/other\nHost domestic02\n  HostName ${relay}\n`, /Include/],
  ] as const) {
    assert.throws(() => store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: `d-${name}`, host: relay, sshConfigFile: write(name, text) }), why);
  }
  assert.throws(() => store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'd-missing', host: relay, sshConfigFile: join(dir, 'nope') }), /cannot be read/);
});

test('allowlist: a stored profile for another host is treated as absent', () => {
  const config = { ...loadConfig(), siteSlotSshAllowedHosts: [] as string[] };
  const store = new MemoryStore(config);
  const old = store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic-main', host: production });
  const kept = store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic02', host: relay });
  config.siteSlotSshAllowedHosts = [relay];
  assert.equal(store.getSiteSlotSshProfile(old.profileId), null);
  assert.equal(store.getSiteSlotSshProfileForSite('domestic-main'), null);
  assert.deepEqual(store.listSiteSlotSshProfiles().map((row) => row.profileId), [kept.profileId]);
  assert.equal(siteSlotSshProfileAllowed(config, null), false);
});
