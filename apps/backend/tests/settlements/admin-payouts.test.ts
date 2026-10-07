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
    expect(list[1]).toMatchObject({ technicianName: 'Tech', maskedPhone: `••••••${phone.slice(-4)}`, amountPaise: 25000, status: 'REQUESTED', paidPaise: null, currentOwedPaise: 30000, currentCashDebtPaise: 5000 });
    expect(res.body).not.toContain(phone);
    expect((await app.inject({ method: 'GET', url: '/admin/payout-requests?status=NOPE', headers: auth(admin) })).statusCode).toBe(400);
  });

  it('pay: nets the CURRENT cash debt first, then pays the rest; PAID + linked entry; ledger debt == cached debt', async () => {
    const { t, requestId } = await openRequest(60000, 10000); // requested 50000
    await ledger(t.technicianId, [{ type: 'CASH_COLLECTED', amountPaise: 5000 }]); // more cash collected after the request
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 15000 } });
    const admin = await makeAdmin();
    const res = await post(admin.token, `/admin/payout-requests/${requestId}/pay`);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'PAID', amountPaise: 50000, paidPaise: 45000, currentOwedPaise: 0, currentCashDebtPaise: 0 });
    const req = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    const payout = await prisma.ledgerEntry.findUniqueOrThrow({ where: { id: req.payoutEntryId! } });
    expect(payout).toMatchObject({ type: 'PAYOUT', amountPaise: 45000 });
    expect(await prisma.ledgerEntry.count({ where: { technicianId: t.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: 15000 } })).toBe(1);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(0);
    expect(await debtBalancePaise(prisma, t.technicianId)).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(0);
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT', actorId: admin.userId } });
    expect(audit.metadata).toMatchObject({ event: 'payout_request_paid', payoutRequestId: requestId, requestedPaise: 50000, offsetPaise: 15000, paidPaise: 45000 });
  });

  it('pay: 409 NOTHING_TO_PAY when debt now covers everything (nothing written); 409 when not open; 404 missing', async () => {
    const { t, requestId } = await openRequest(30000); // requested 30000
    await ledger(t.technicianId, [{ type: 'CASH_COLLECTED', amountPaise: 30000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 30000 } });
    const admin = await makeAdminToken();
    const res = await post(admin, `/admin/payout-requests/${requestId}/pay`);
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'NOTHING_TO_PAY', message: 'Nothing is owed after settling cash debt — reject this request instead' });
    expect(await prisma.ledgerEntry.count({ where: { type: { in: ['PAYOUT', 'CASH_DEBT_OFFSET'] } } })).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(30000);
    expect((await post(admin, `/admin/payout-requests/${requestId}/reject`, { reason: 'Covered by your cash collections' })).statusCode).toBe(200);
    const notOpen = await post(admin, `/admin/payout-requests/${requestId}/pay`);
    expect(notOpen.json()).toEqual({ code: 'PAYOUT_REQUEST_NOT_OPEN', message: 'This payout request is no longer open' });
    expect((await post(admin, '/admin/payout-requests/00000000-0000-0000-0000-000000000000/pay')).statusCode).toBe(404);
    expect((await post(admin, '/admin/payout-requests/not-a-uuid/pay')).statusCode).toBe(400);
  });

  it('two concurrent pays of one request → exactly one PAYOUT', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const [a, b] = await Promise.all([post(admin, `/admin/payout-requests/${requestId}/pay`), post(admin, `/admin/payout-requests/${requestId}/pay`)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(1);
  });

  it('pay racing reject → exactly one terminal state, at most one PAYOUT', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const [p, r] = await Promise.all([post(admin, `/admin/payout-requests/${requestId}/pay`), post(admin, `/admin/payout-requests/${requestId}/reject`, { reason: 'Duplicate' })]);
    expect([p.statusCode, r.statusCode].sort()).toEqual([200, 409]);
    const final = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(final.status === 'PAID' ? 1 : 0);
  });

  it('reject: reason rules; REJECTED + note; audited; technician sees it', async () => {
    const { t, requestId } = await openRequest(60000);
    const admin = await makeAdmin();
    const url = `/admin/payout-requests/${requestId}/reject`;
    for (const payload of [undefined, {}, { reason: '  ' }, { reason: 'x'.repeat(501) }, { reason: 'call 98765 43210' }, { reason: 'ok', extra: 1 }]) {
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
