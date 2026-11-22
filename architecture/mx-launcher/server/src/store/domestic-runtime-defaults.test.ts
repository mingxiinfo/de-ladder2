// L2 (de-ladder2 docs/58): MX_DOMESTIC_DEFAULT_SITE_ID / MX_DOMESTIC_DEFAULT_BOOTSTRAP_HOST.
// Unset keeps the L1 defaults; set, a new Domestic runtime config starts from s2's test relay.
import 'reflect-metadata';
import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../config.js';
import { buildSiteSlotDomesticRuntimeConfig, domesticRuntimeDefaults } from './domain.js';

test('unset: the L1 defaults', () => {
  const config = { ...loadConfig(), domesticDefaultSiteId: null, domesticDefaultBootstrapHost: null };
  assert.deepEqual(domesticRuntimeDefaults(config), { siteId: 'domestic-main', bootstrapHost: 'h2i.minsight-ai.com' });
  const built = buildSiteSlotDomesticRuntimeConfig(config, {}, null);
  assert.equal(built.siteId, 'domestic-main');
  assert.equal(built.edge.publicBaseUrl, 'https://h2i.minsight-ai.com');
});

test('set: a new config starts from the test relay, and typed values still win', () => {
  const config = { ...loadConfig(), domesticDefaultSiteId: 'domestic02', domesticDefaultBootstrapHost: 'mincave.minsight-ai.com' };
  assert.deepEqual(domesticRuntimeDefaults(config), { siteId: 'domestic02', bootstrapHost: 'mincave.minsight-ai.com' });
  const built = buildSiteSlotDomesticRuntimeConfig(config, {}, null);
  assert.equal(built.siteId, 'domestic02');
  assert.equal(built.edge.publicBaseUrl, 'https://mincave.minsight-ai.com');
  const typed = buildSiteSlotDomesticRuntimeConfig(config, { siteId: 'domestic03', bootstrapHost: 'other.example.com' }, null);
  assert.equal(typed.siteId, 'domestic03');
  assert.equal(typed.edge.publicBaseUrl, 'https://other.example.com');
});

test('bad values fall back to the L1 defaults', () => {
  const config = { ...loadConfig(), domesticDefaultSiteId: 'bad id!', domesticDefaultBootstrapHost: 'not a host' };
  assert.deepEqual(domesticRuntimeDefaults(config), { siteId: 'domestic-main', bootstrapHost: 'h2i.minsight-ai.com' });
});
