// L2 (de-ladder2 docs/52): MX_SITE_SLOT_SSH_ALLOWED_HOSTS keeps s2's Launcher from SSHing anywhere
// but its test relay (domestic02). Empty keeps the L1 behaviour.
import 'reflect-metadata';
import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../config.js';
import { MemoryStore } from './memory.js';
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

test('allowlist: only listed hosts can get a profile, and no per-profile ssh_config', () => {
  const config = { ...loadConfig(), siteSlotSshAllowedHosts: [relay] };
  const store = new MemoryStore(config);
  assert.equal(store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic02', host: relay }).host, relay);
  assert.throws(
    () => store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic-main', host: production }),
    /not in MX_SITE_SLOT_SSH_ALLOWED_HOSTS/,
  );
  assert.throws(
    () => store.upsertSiteSlotSshProfile({ kind: 'domestic', siteId: 'domestic02b', host: relay, sshConfigFile: '/tmp/ssh_config' }),
    /sshConfigFile is not allowed/,
  );
  assert.doesNotThrow(() => assertSiteSlotSshHostAllowed(config, relay.toUpperCase(), null));
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
