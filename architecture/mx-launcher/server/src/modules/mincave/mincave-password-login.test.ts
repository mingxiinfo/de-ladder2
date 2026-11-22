// L2 (de-ladder2 docs/49): MX_MINCAVE_PASSWORD_LOGIN_ENABLED lets a Launcher
// account/password token into MinCave as an employee. Off keeps the L1 rule (Feishu only).
import 'reflect-metadata';
import assert from 'node:assert/strict';
import test from 'node:test';
import { ForbiddenException, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { loadConfig } from '../../config.js';
import { MemoryStore } from '../../store/memory.js';
import { MinCaveService } from './mincave.service.js';

function fixture(options: { enabled: boolean; tenantKey?: string | null }) {
  const config = {
    ...loadConfig(),
    mincaveFeishuTenantKey: options.tenantKey === undefined ? 'minsight-tenant' : options.tenantKey,
    mincaveInitialAdminUserId: 'admin',
    mincavePasswordLoginEnabled: options.enabled,
  };
  const store = new MemoryStore(config);
  store.bootstrapUserCenter();
  const service = new MinCaveService(config, store);
  const user = (id: string, extra: Record<string, unknown> = {}) =>
    store.createUserCenterUser({
      userId: id,
      account: id,
      displayName: `Name ${id}`,
      roleIds: ['mx-user'],
      externalIds: { feishuSubject: `minsight-tenant:ou_${id}` },
      profile: { department: '研发' },
      ...extra,
    });
  const password = (id: string, overrides: Record<string, unknown> = {}) =>
    store.issueUserCenterToken({
      subjectKind: 'user',
      subjectId: id,
      audience: 'mx-sdk',
      appId: 'mx-h2i',
      scopes: ['auth.read'],
      authProvider: 'local-password',
      ...overrides,
    }).token;
  const feishu = (id: string) =>
    store.issueUserCenterToken({
      subjectKind: 'user',
      subjectId: id,
      audience: 'mx-sdk',
      appId: 'mx-h2i',
      scopes: ['auth.read'],
      authProvider: 'feishu',
      verifiedFeishuIdentity: { tenantKey: 'minsight-tenant', subject: `minsight-tenant:ou_${id}` },
    }).token;
  user('admin');
  user('staff');
  const bearer = (token: string) => `Bearer ${token}`;
  return { config, store, service, user, password, feishu, bearer };
}

test('switch off: a password token is refused exactly as in L1', async () => {
  const f = fixture({ enabled: false });
  await assert.rejects(f.service.session(f.bearer(f.password('staff'))), (err: unknown) => {
    assert.ok(err instanceof UnauthorizedException);
    assert.equal((err.getResponse() as { code: string }).code, 'feishu_login_required');
    return true;
  });
  await assert.rejects(f.service.devices(f.bearer(f.password('staff'))), UnauthorizedException);
});

test('switch on: a password account enters as employee, never a member, never admin', async () => {
  const f = fixture({ enabled: true });
  const token = f.password('staff');
  const device = { device: { deviceId: 'dev-1', deviceLabel: 'QA Mac', platform: 'darwin' } };
  const result = await f.service.session(f.bearer(token), device);
  assert.equal(result.allowed, true);
  assert.equal(result.role, 'employee');
  assert.equal(result.canManage, false);
  assert.equal(result.userId, 'staff');
  assert.ok(result.applications.length > 0, 'the default workspace applications are listed');
  assert.equal(f.store.listMinCaveMembers().length, 0, 'no MinCave member record is created');
  assert.deepEqual((await f.service.devices(f.bearer(token))).devices.map((row) => row.deviceId), ['dev-1']);
  await assert.rejects(f.service.members(f.bearer(token)), UnauthorizedException);
});

test('switch on: the password admin account still gets employee only', async () => {
  const f = fixture({ enabled: true });
  const result = await f.service.session(f.bearer(f.password('admin')));
  assert.equal(result.role, 'employee');
  assert.equal(result.canManage, false);
  await assert.rejects(f.service.members(f.bearer(f.password('admin'))), UnauthorizedException);
});

test('switch on: user-center checks still apply to password accounts', async () => {
  const f = fixture({ enabled: true });
  // The token issuer already refuses denied or disabled accounts; these cover access
  // revoked after the token was issued.
  const refused = (err: unknown) => err instanceof ForbiddenException || err instanceof UnauthorizedException;
  f.user('denied');
  const deniedToken = f.password('denied');
  f.store.createUserCenterUser({ userId: 'denied', deniedAppIds: ['mx-h2i'] });
  await assert.rejects(f.service.session(f.bearer(deniedToken)), refused);
  f.user('gone');
  const goneToken = f.password('gone');
  f.store.createUserCenterUser({ userId: 'gone', status: 'disabled' });
  await assert.rejects(f.service.session(f.bearer(goneToken)), refused);
  await assert.rejects(
    f.service.session(f.bearer(f.password('staff', { appId: 'other-app' }))),
    UnauthorizedException,
  );
  await assert.rejects(
    f.service.session(f.bearer(f.password('staff', { scopes: ['appcenter.read'] }))),
    UnauthorizedException,
  );
  await assert.rejects(f.service.session(f.bearer('not-a-token')), UnauthorizedException);
});

test('switch on: Feishu logins keep the L1 path, including admin', async () => {
  const f = fixture({ enabled: true });
  assert.equal((await f.service.session(f.bearer(f.feishu('admin')))).role, 'admin');
  assert.equal((await f.service.session(f.bearer(f.feishu('staff')))).role, 'employee');
  assert.equal(f.store.listMinCaveMembers().length, 2);
});

test('switch on without a Feishu tenant: password works, Feishu is still unavailable', async () => {
  const f = fixture({ enabled: true, tenantKey: null });
  assert.equal((await f.service.session(f.bearer(f.password('staff')))).role, 'employee');
  await assert.rejects(f.service.session(f.bearer(f.feishu('staff'))), ServiceUnavailableException);
});
