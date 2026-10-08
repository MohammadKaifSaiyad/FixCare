import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdmin, makeAdminToken, makeCustomer } from '../bookings/helpers.js';
import { debtBalancePaise, payableBalancePaise } from '../../src/modules/settlements/settlements.service.js';
import { auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const REF = 'UTR-TEST-0001';
const post = (token: string, url: string, payload?: object) =>
  app.inject({ method: 'POST', url, headers: auth(token), ...(payload === undefined ? {} : { payload }) });

/** A technician owed `owed`, holding `debt` (ledger + cached column consistent), with an open request. */
async function openRequest(owed: number, debt = 0) {
  const t = await makeTechnician(['AC']);
  await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: owed }, ...(debt ? [{ type: 'CASH_COLLECTED' as const, amountPaise: debt }] : [])]);
  if (debt) await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: debt } });
  const r = (await post(t.token, '/technician/me/payout-requests')).json() as { id: string };
  return { t, requestId: r.id };
}

describe('admin payout requests', () => {
  it('walls: 401 without a token; 403 for SUPPORT, customer, technician', async () => {
    const { t, requestId } = await openRequest(60000);
    const callers = [await makeAdminToken('SUPPORT'), (await makeCustomer()).token, t.token];
    const routes = [
      { method: 'GET' as const, url: '/admin/payout-requests' },
      { method: 'POST' as const, url: `/admin/payout-requests/${requestId}/pay` },
      { method: 'POST' as const, url: `/admin/payout-requests/${requestId}/reject`, payload: { reason: 'x' } },
    ];
    for (const r of routes) {
      expect((await app.inject(r)).statusCode).toBe(401);
      for (const token of callers) expect((await app.inject({ ...r, headers: auth(token) })).statusCode).toBe(403);
    }
  });

  it('lists oldest first with masked phone + current balances; filters by status', async () => {
    const a = await openRequest(60000);
    const b = await openRequest(30000, 5000);
    const admin = await makeAdminToken();
    const res = await app.inject({ method: 'GET', url: '/admin/payout-requests?status=REQUESTED', headers: auth(admin) });
    expect(res.statusCode).toBe(200);
    const list = res.json() as Array<Record<string, unknown>>;
    expect(list.map((r) => r.id)).toEqual([a.requestId, b.requestId]);
    const phone = (await prisma.user.findUniqueOrThrow({ where: { id: b.t.userId } })).phone;
    expect(list[1]).toMatchObject({ technicianName: 'Tech', maskedPhone: `••••••${phone.slice(-4)}`, amountPaise: 25000, status: 'REQUESTED', paidPaise: null, currentOwedPaise: 30000, currentCashDebtPaise: 5000, currentNetPaise: 25000, technicianStatus: 'VERIFIED' });
    expect(list[0]).toMatchObject({ transferReference: null });
    expect(res.body).not.toContain(phone);
    expect((await app.inject({ method: 'GET', url: '/admin/payout-requests?status=NOPE', headers: auth(admin) })).statusCode).toBe(400);
  });

  it('pay: nets the CURRENT cash debt first, then pays the rest; PAID + linked entry; ledger debt == cached debt', async () => {
    const { t, requestId } = await openRequest(60000, 10000); // requested 50000
    await ledger(t.technicianId, [{ type: 'CASH_COLLECTED', amountPaise: 5000 }]); // more cash collected after the request
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 15000 } });
    const admin = await makeAdmin();
    const stale = await post(admin.token, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 50000, transferReference: REF });
    expect(stale.statusCode).toBe(409);
    expect(stale.json()).toEqual({ code: 'PAYOUT_EXCEEDS_NET', message: 'That is more than FixCare owes (₹450) — escalate before recording it' });
    expect(await prisma.ledgerEntry.count({ where: { type: { in: ['PAYOUT', 'CASH_DEBT_OFFSET'] } } })).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(15000);
    expect((await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } })).status).toBe('REQUESTED');
    const res = await post(admin.token, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 45000, transferReference: REF });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'PAID', amountPaise: 50000, paidPaise: 45000, currentOwedPaise: 0, currentCashDebtPaise: 0, transferReference: REF });
    const req = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    const payout = await prisma.ledgerEntry.findUniqueOrThrow({ where: { id: req.payoutEntryId! } });
    expect(payout).toMatchObject({ type: 'PAYOUT', amountPaise: 45000 });
    expect(req.transferReference).toBe(REF);
    expect(await prisma.ledgerEntry.count({ where: { technicianId: t.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: 15000 } })).toBe(1);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(0);
    expect(await debtBalancePaise(prisma, t.technicianId)).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(0);
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT', actorId: admin.userId } });
    expect(audit.metadata).toMatchObject({ event: 'payout_request_paid', payoutRequestId: requestId, requestedPaise: 50000, offsetPaise: 15000, paidPaise: 45000, transferReference: REF, payoutEntryId: payout.id });
  });

  it('pay: transferring MORE than the net → 409 PAYOUT_EXCEEDS_NET, nothing written', async () => {
    const { t, requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const res = await post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 60001, transferReference: REF });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'PAYOUT_EXCEEDS_NET', message: 'That is more than FixCare owes (₹600) — escalate before recording it' });
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(0);
    expect((await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } })).status).toBe('REQUESTED');
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(60000);
  });

  it('pay: transfer == net → 200 and nothing remains payable', async () => {
    const { t, requestId } = await openRequest(60000);
    const res = await post(await makeAdminToken(), `/admin/payout-requests/${requestId}/pay`, { amountPaise: 60000, transferReference: REF });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'PAID', paidPaise: 60000, currentOwedPaise: 0, currentNetPaise: 0 });
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(0);
  });

  it('pay: earnings credited after the transfer → records what was transferred; the rest stays owed; debt consistent', async () => {
    const { t, requestId } = await openRequest(60000, 10000); // requested 50000; cash debt 10000
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 20000 }]); // net is now 70000
    const admin = await makeAdmin();
    const ok = await post(admin.token, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 50000, transferReference: REF });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toMatchObject({ status: 'PAID', amountPaise: 50000, paidPaise: 50000, currentOwedPaise: 20000, currentCashDebtPaise: 0, currentNetPaise: 20000 });
    const req = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    expect(await prisma.ledgerEntry.findUniqueOrThrow({ where: { id: req.payoutEntryId! } })).toMatchObject({ type: 'PAYOUT', amountPaise: 50000 });
    expect(await prisma.ledgerEntry.count({ where: { technicianId: t.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: 10000 } })).toBe(1);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(20000);
    expect(await debtBalancePaise(prisma, t.technicianId)).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(0);
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT', actorId: admin.userId } });
    expect(audit.metadata).toMatchObject({ requestedPaise: 50000, offsetPaise: 10000, paidPaise: 50000, netPaise: 70000 });
  });

  it('pay: a transfer reference closes at most one request → 409 TRANSFER_REFERENCE_USED, nothing written', async () => {
    const a = await openRequest(60000);
    const b = await openRequest(40000);
    const admin = await makeAdminToken();
    expect((await post(admin, `/admin/payout-requests/${a.requestId}/pay`, { amountPaise: 60000, transferReference: REF })).statusCode).toBe(200);
    const dup = await post(admin, `/admin/payout-requests/${b.requestId}/pay`, { amountPaise: 40000, transferReference: REF });
    expect(dup.statusCode).toBe(409);
    expect(dup.json()).toEqual({ code: 'TRANSFER_REFERENCE_USED', message: 'This transfer reference was already used for another payout' });
    expect(await prisma.ledgerEntry.count({ where: { technicianId: b.t.technicianId, type: 'PAYOUT' } })).toBe(0);
    expect((await prisma.payoutRequest.findUniqueOrThrow({ where: { id: b.requestId } })).status).toBe('REQUESTED');
    expect((await post(admin, `/admin/payout-requests/${b.requestId}/pay`, { amountPaise: 40000, transferReference: 'UTR-OTHER-2' })).statusCode).toBe(200);
  });

  it('pay: two concurrent pays of different requests with one reference → exactly one wins', async () => {
    const a = await openRequest(60000);
    const b = await openRequest(40000);
    const admin = await makeAdminToken();
    const [x, y] = await Promise.all([
      post(admin, `/admin/payout-requests/${a.requestId}/pay`, { amountPaise: 60000, transferReference: REF }),
      post(admin, `/admin/payout-requests/${b.requestId}/pay`, { amountPaise: 40000, transferReference: REF }),
    ]);
    expect([x.statusCode, y.statusCode].sort()).toEqual([200, 409]);
    const loser = x.statusCode === 409 ? x : y;
    expect(loser.json().code).toBe('TRANSFER_REFERENCE_USED');
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(1);
  });

  it('pay: a deleted technician is not paid → 409 TECHNICIAN_DELETED; a SUSPENDED one still is', async () => {
    const a = await openRequest(60000);
    const b = await openRequest(40000);
    await prisma.technician.update({ where: { id: a.t.technicianId }, data: { deletedAt: new Date() } });
    await prisma.technician.update({ where: { id: b.t.technicianId }, data: { status: 'SUSPENDED' } });
    const admin = await makeAdminToken();
    const res = await post(admin, `/admin/payout-requests/${a.requestId}/pay`, { amountPaise: 60000, transferReference: REF });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'TECHNICIAN_DELETED', message: 'This technician account was removed — escalate before paying' });
    expect(await prisma.ledgerEntry.count({ where: { technicianId: a.t.technicianId, type: 'PAYOUT' } })).toBe(0);
    expect((await prisma.payoutRequest.findUniqueOrThrow({ where: { id: a.requestId } })).status).toBe('REQUESTED');
    expect((await post(admin, `/admin/payout-requests/${b.requestId}/pay`, { amountPaise: 40000, transferReference: 'UTR-OTHER-3' })).statusCode).toBe(200);
  });

  it('pay: missing or invalid body → 400, nothing written', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const url = `/admin/payout-requests/${requestId}/pay`;
    const bad: Array<object | undefined> = [
      undefined, {}, { amountPaise: 60000 }, { transferReference: REF },
      { amountPaise: 0, transferReference: REF }, { amountPaise: -5, transferReference: REF }, { amountPaise: 600.5, transferReference: REF }, { amountPaise: '60000', transferReference: REF },
      { amountPaise: 60000, transferReference: REF, extra: 1 },
      { amountPaise: 60000, transferReference: 'abc' }, { amountPaise: 60000, transferReference: '   ab  ' },
      { amountPaise: 60000, transferReference: 'x'.repeat(65) }, { amountPaise: 60000, transferReference: 'UTR 1234' }, { amountPaise: 60000, transferReference: 'me@okbank' },
    ];
    for (const payload of bad) expect((await post(admin, url, payload)).statusCode).toBe(400);
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(0);
  });

  it('pay: the reference is trimmed; the technician DTO never exposes it', async () => {
    const { t, requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const res = await post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 60000, transferReference: '  UTR/2026-10/AB1  ' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ transferReference: 'UTR/2026-10/AB1' });
    const mine = await app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(t.token) });
    expect(mine.json().latestPayoutRequest).not.toHaveProperty('transferReference');
    expect(mine.body).not.toContain('UTR/2026-10/AB1');
  });

  it('list: a SUSPENDED technician shows technicianStatus SUSPENDED', async () => {
    const { t } = await openRequest(60000);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { status: 'SUSPENDED' } });
    const list = (await app.inject({ method: 'GET', url: '/admin/payout-requests', headers: auth(await makeAdminToken()) })).json() as Array<Record<string, unknown>>;
    expect(list[0]).toMatchObject({ technicianStatus: 'SUSPENDED' });
  });

  it('pay: 409 NOTHING_TO_PAY when debt now covers everything (nothing written); 409 when not open; 404 missing', async () => {
    const { t, requestId } = await openRequest(30000); // requested 30000
    await ledger(t.technicianId, [{ type: 'CASH_COLLECTED', amountPaise: 30000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 30000 } });
    const admin = await makeAdminToken();
    const res = await post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 30000, transferReference: REF });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'NOTHING_TO_PAY', message: 'Nothing is owed after settling cash debt — reject this request instead' });
    expect(await prisma.ledgerEntry.count({ where: { type: { in: ['PAYOUT', 'CASH_DEBT_OFFSET'] } } })).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(30000);
    expect((await post(admin, `/admin/payout-requests/${requestId}/reject`, { reason: 'Covered by your cash collections' })).statusCode).toBe(200);
    const notOpen = await post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 30000, transferReference: REF });
    expect(notOpen.json()).toEqual({ code: 'PAYOUT_REQUEST_NOT_OPEN', message: 'This payout request is no longer open' });
    expect((await post(admin, '/admin/payout-requests/00000000-0000-0000-0000-000000000000/pay', { amountPaise: 100, transferReference: REF })).statusCode).toBe(404);
    expect((await post(admin, '/admin/payout-requests/not-a-uuid/pay', { amountPaise: 100, transferReference: REF })).statusCode).toBe(400);
  });

  it('two concurrent pays of one request → exactly one PAYOUT', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const [a, b] = await Promise.all([post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 60000, transferReference: REF }), post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 60000, transferReference: REF })]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(1);
  });

  it('pay racing reject → exactly one terminal state, at most one PAYOUT', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const [p, r] = await Promise.all([post(admin, `/admin/payout-requests/${requestId}/pay`, { amountPaise: 60000, transferReference: REF }), post(admin, `/admin/payout-requests/${requestId}/reject`, { reason: 'Duplicate' })]);
    expect([p.statusCode, r.statusCode].sort()).toEqual([200, 409]);
    const final = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(final.status === 'PAID' ? 1 : 0);
  });

  it('reject: reason rules; REJECTED + note; audited; technician sees it', async () => {
    const { t, requestId } = await openRequest(60000);
    const admin = await makeAdmin();
    const url = `/admin/payout-requests/${requestId}/reject`;
    for (const payload of [undefined, {}, { reason: '  ' }, { reason: 'x'.repeat(501) }, { reason: 'call 98765 43210' }, { reason: 'pay me at name@okbank' }, { reason: 'ok', extra: 1 }]) {
      expect((await post(admin.token, url, payload)).statusCode).toBe(400);
    }
    const res = await post(admin.token, url, { reason: 'Bank details not confirmed yet' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'REJECTED', reviewNote: 'Bank details not confirmed yet', paidPaise: null });
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT', actorId: admin.userId } });
    expect(audit.metadata).toMatchObject({ event: 'payout_request_rejected', payoutRequestId: requestId });
    const latest = (await app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(t.token) })).json().latestPayoutRequest;
    expect(latest).toMatchObject({ status: 'REJECTED', reviewNote: 'Bank details not confirmed yet' });
  });
});
