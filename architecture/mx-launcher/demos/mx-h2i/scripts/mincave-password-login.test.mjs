// L2 (de-ladder2 docs/49): the hidden MinCave account/password login.
// Off by default (L1 behaviour: MinCave is Feishu only); MX_H2I_MINCAVE_PASSWORD_LOGIN=1 turns it on.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const { createMincaveAdminBridge } = require('../src/mincave-admin.cjs');
const mainSource = await readFile(new URL('../src/main-runtime.cjs', import.meta.url), 'utf8');
const rendererSource = await readFile(new URL('../src/renderer.js', import.meta.url), 'utf8');

function bridge({ allowPasswordLogin, response }) {
  const calls = [];
  const auth = { provider: 'local-password', accessToken: 'token-1', subject: 'user:staff' };
  const value = createMincaveAdminBridge({
    getRuntime: () => ({ auth, installation: {} }),
    fetch: async (url) => {
      calls.push(url);
      return { ok: true, json: async () => response };
    },
    resolveBaseUrl: async () => 'http://127.0.0.1:18090',
    ...(allowPasswordLogin ? { allowPasswordLogin } : {}),
  });
  return { value, calls, auth };
}

const employee = { allowed: true, role: 'employee', canManage: false, userId: 'staff', applications: [] };

test('a password login is refused before any request unless explicitly allowed', async () => {
  for (const allowPasswordLogin of [undefined, () => false, () => 'yes']) {
    const b = bridge({ allowPasswordLogin, response: employee });
    await assert.rejects(b.value.checkLogin(b.auth, 'http://127.0.0.1:18090'), (err) => err.code === 'feishu_login_required');
    assert.deepEqual(b.calls, []);
  }
});

test('when allowed, a password login is admitted only as a non-managing employee', async () => {
  const ok = bridge({ allowPasswordLogin: () => true, response: employee });
  const access = await ok.value.checkLogin(ok.auth, 'http://127.0.0.1:18090');
  assert.equal(access.role, 'employee');
  assert.equal(access.canManage, false);
  assert.equal(ok.calls.length, 1);
  const elevated = bridge({ allowPasswordLogin: () => true, response: { ...employee, role: 'admin', canManage: true } });
  await assert.rejects(elevated.value.checkLogin(elevated.auth, 'http://127.0.0.1:18090'), (err) => err.code === 'invalid_access_response');
});

test('anything other than Feishu or password stays refused even when allowed', async () => {
  const b = bridge({ allowPasswordLogin: () => true, response: employee });
  await assert.rejects(b.value.checkLogin({ ...b.auth, provider: 'anonymous' }, 'http://127.0.0.1:18090'), (err) => err.code === 'feishu_login_required');
  await assert.rejects(b.value.checkLogin({ ...b.auth, provider: null }, 'http://127.0.0.1:18090'), (err) => err.code === 'feishu_login_required');
});

test('main process: the switch is one env var and guards the employee login IPC in MinCave', () => {
  assert.match(mainSource, /function mincavePasswordLoginEnabled\(\) \{\n  return \/\^\(1\|true\|yes\|on\)\$\/i\.test\(String\(process\.env\.MX_H2I_MINCAVE_PASSWORD_LOGIN \|\| ''\)\.trim\(\)\);\n\}/);
  assert.match(mainSource, /'mx-h2i:login-employee', async \(_event, input\) => \{\n    if \(MINCAVE_UI_ENABLED && !mincavePasswordLoginEnabled\(\)\) throw new Error\('请使用飞书登录 MinCave。'\);/);
  assert.match(mainSource, /allowPasswordLogin: \(\) => mincavePasswordLoginEnabled\(\),/);
  assert.match(mainSource, /mincavePasswordLogin: MINCAVE_UI_ENABLED \? mincavePasswordLoginEnabled\(\) : undefined,/);
});

test('renderer: the MinCave password form exists only when the main process allows it', () => {
  assert.match(rendererSource, /const passwordForm = state\.mincavePasswordLogin === true \? `/);
  assert.match(rendererSource, /<form class="mincave-password-login" data-form-action="login-employee"/);
  assert.match(rendererSource, /passwordLogin: state\.mincavePasswordLogin === true,/);
});
