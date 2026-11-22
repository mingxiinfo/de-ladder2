import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const rendererSource = readFileSync(
  fileURLToPath(new URL('../renderer.js', import.meta.url)),
  'utf8'
);

function functionSource(source, name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} must exist`);
  const parametersStart = source.indexOf('(', start);
  let parametersDepth = 0;
  let parametersEnd = -1;
  for (let index = parametersStart; index < source.length; index += 1) {
    if (source[index] === '(') parametersDepth += 1;
    if (source[index] === ')') parametersDepth -= 1;
    if (parametersDepth === 0) {
      parametersEnd = index;
      break;
    }
  }
  const bodyStart = source.indexOf('{', parametersEnd);
  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`${name} is not balanced`);
}

const canonicalHostMatch = rendererSource.match(
  /const MX_DEFAULT_PUBLIC_BOOTSTRAP_HOST = '([^']+)';/
);
assert.ok(canonicalHostMatch, 'canonical public bootstrap host must be declared');
const canonicalHost = canonicalHostMatch[1];
assert.equal(canonicalHost, 'h2i.minsight-ai.com');

const runtimeHelpers = Function(
  `
const MX_DEFAULT_PUBLIC_BOOTSTRAP_HOST = ${JSON.stringify(canonicalHost)};
function positiveNumberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}
const DOMESTIC_RUNTIME_SITE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;
${functionSource(rendererSource, 'domesticRuntimeServerDefaults')}
${functionSource(rendererSource, 'domesticRuntimeDefaultConfig')}
${functionSource(rendererSource, 'domesticRuntimeBootstrapParts')}
${functionSource(rendererSource, 'domesticRuntimePublicUrl')}
${functionSource(rendererSource, 'domesticRuntimeBootstrapSummaryLabel')}
return {
  domesticRuntimeDefaultConfig,
  domesticRuntimeBootstrapParts,
  domesticRuntimePublicUrl,
  domesticRuntimeBootstrapSummaryLabel
};
`
)();

const draft = runtimeHelpers.domesticRuntimeDefaultConfig('domestic-main');
assert.equal(draft.edge.publicBaseUrl, 'https://h2i.minsight-ai.com');
assert.equal(draft.edge.bind, '127.0.0.1', 'a new config must not expose the legacy listener by default');
assert.equal(draft.edge.port, 18090, 'legacy edge port remains independently configurable');

assert.deepEqual(
  runtimeHelpers.domesticRuntimeBootstrapParts(draft),
  {
    protocol: 'https',
    host: 'h2i.minsight-ai.com',
    port: 443
  }
);
assert.deepEqual(
  runtimeHelpers.domesticRuntimeBootstrapParts({
    edge: {
      bind: '0.0.0.0',
      port: 18090,
      publicBaseUrl: 'http://legacy.example:18090'
    }
  }),
  {
    protocol: 'http',
    host: 'legacy.example',
    port: 18090
  },
  'an existing saved legacy URL is rendered honestly instead of silently rewritten'
);
assert.deepEqual(
  runtimeHelpers.domesticRuntimeBootstrapParts({ edge: { bind: '0.0.0.0', port: 18090 } }),
  {
    protocol: 'https',
    host: 'h2i.minsight-ai.com',
    port: 443
  },
  'a missing public URL falls back to the canonical HTTPS identity, not the SSH host'
);

assert.equal(
  runtimeHelpers.domesticRuntimePublicUrl({
    protocol: 'https',
    host: canonicalHost,
    port: 443
  }),
  'https://h2i.minsight-ai.com'
);
assert.match(
  runtimeHelpers.domesticRuntimeBootstrapSummaryLabel({
    protocol: 'http',
    host: canonicalHost,
    port: 18090
  }),
  /Non-canonical bootstrap draft/
);

assert.doesNotMatch(
  rendererSource,
  /function domesticRuntimeDefaultBootstrapHost\(/,
  'the TLS bootstrap identity must not be inferred from a Domestic SSH profile or plan'
);
assert.match(rendererSource, /Legacy \/ Diagnostic Edge Bind/);
assert.match(rendererSource, /Legacy \/ Diagnostic Edge Port/);
assert.match(
  rendererSource,
  /data-domestic-runtime-public-summary-label/,
  'the public summary must distinguish the current form draft'
);
assert.match(
  functionSource(rendererSource, 'bindDomesticRuntimeControls'),
  /refreshDomesticRuntimeDraftSummary\(root\)/,
  'editing a runtime field must refresh the visible draft summary'
);

// L2 (de-ladder2 docs/58): server-provided defaults, a typeable site, unsaved edits kept per site
const withDefaults = Function(
  'defaults',
  `
const MX_DEFAULT_PUBLIC_BOOTSTRAP_HOST = ${JSON.stringify(canonicalHost)};
const DOMESTIC_RUNTIME_SITE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;
const state = { domesticRuntime: { defaults } };
${functionSource(rendererSource, 'domesticRuntimeServerDefaults')}
${functionSource(rendererSource, 'domesticRuntimeDefaultConfig')}
${functionSource(rendererSource, 'domesticRuntimeBootstrapParts')}
return { domesticRuntimeServerDefaults, domesticRuntimeDefaultConfig, domesticRuntimeBootstrapParts };
`
);
const l2 = withDefaults({ siteId: 'domestic02', bootstrapHost: 'mincave.minsight-ai.com' });
assert.deepEqual(l2.domesticRuntimeServerDefaults(), { siteId: 'domestic02', bootstrapHost: 'mincave.minsight-ai.com' });
assert.equal(l2.domesticRuntimeDefaultConfig().siteId, 'domestic02');
assert.equal(l2.domesticRuntimeDefaultConfig('domestic03').edge.publicBaseUrl, 'https://mincave.minsight-ai.com');
assert.equal(l2.domesticRuntimeBootstrapParts({ edge: {} }).host, 'mincave.minsight-ai.com');
const l1 = withDefaults(null);
assert.deepEqual(l1.domesticRuntimeServerDefaults(), { siteId: 'domestic-main', bootstrapHost: canonicalHost }, 'no server defaults keeps L1');
assert.equal(withDefaults({ siteId: 'bad id!', bootstrapHost: '' }).domesticRuntimeServerDefaults().siteId, 'domestic-main');
const panel = functionSource(rendererSource, 'renderDomesticRuntimeConfigPanel');
assert.match(panel, /<input data-domestic-runtime-site data-domestic-runtime-field="siteId" list="domestic-runtime-site-options"/, 'the site is typeable');
assert.match(panel, /<datalist id="domestic-runtime-site-options">/);
assert.doesNotMatch(panel, /<select data-domestic-runtime-site/);
const bind = functionSource(rendererSource, 'bindDomesticRuntimeControls');
assert.match(bind, /DOMESTIC_RUNTIME_SITE_ID_PATTERN\.test\(typed\)/, 'typed site ids are validated');
assert.match(bind, /drafts\[currentSiteId\] = \{ \.\.\.\(drafts\[currentSiteId\] \|\| \{\}\), \[field\.dataset\.domesticRuntimeField\]: field\.value \}/, 'edits are kept per site');
assert.match(bind, /field\.value = draft\[name\]/, 'kept edits are restored after a re-render');
assert.match(functionSource(rendererSource, 'domesticRuntimeConfigForRender'), /state\.domesticRuntime\.selectedSiteId \? null : configs\[0\]/, 'a typed new site does not borrow another site config');

console.log('domestic runtime config UI contract: ok');
