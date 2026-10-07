import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer } from '../bookings/helpers.js';
import { auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const request = (token: string) => app.inject({ method: 'POST', url: '/technician/me/payout-requests', headers: auth(token) });

describe('POST /technician/me/payout-requests', () => {
  it('requests the NET amount (owed − cash debt); audited; returned as the latest request', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 40000 } });
    const res = await request(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'REQUESTED', amountPaise: 20000, reviewedAt: null, reviewNote: null });
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT' } });
    expect(audit.metadata).toMatchObject({ event: 'payout_requested', technicianId: t.technicianId, amountPaise: 20000 });
    expect((await app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(t.token) })).json().latestPayoutRequest.status).toBe('REQUESTED');
  });

  it('422 PAYOUT_BELOW_MINIMUM when the net amount is under ₹100', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 15000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 6000 } }); // net 9000
    const res = await request(t.token);
    expect(res.statusCode).toBe(422);
    expect(res.json()).toEqual({ code: 'PAYOUT_BELOW_MINIMUM', message: 'Payouts start at ₹100' });
    expect(await prisma.payoutRequest.count()).toBe(0);
  });

  it('409 PAYOUT_ALREADY_REQUESTED while one is open; allowed again after it is paid or rejected', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    expect((await request(t.token)).statusCode).toBe(200);
    const again = await request(t.token);
    expect(again.statusCode).toBe(409);
    expect(again.json()).toEqual({ code: 'PAYOUT_ALREADY_REQUESTED', message: 'You already have a payout request in progress' });
    await prisma.payoutRequest.updateMany({ data: { status: 'REJECTED', reviewNote: 'x', reviewedAt: new Date() } });
    expect((await request(t.token)).statusCode).toBe(200);
  });

  it('two simultaneous requests → exactly one is created', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    const [a, b] = await Promise.all([request(t.token), request(t.token)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await prisma.payoutRequest.count({ where: { status: 'REQUESTED' } })).toBe(1);
  });

  it('a SUSPENDED technician can request; a customer cannot; no token → 401', async () => {
    const t = await makeTechnician(['AC'], 'SUSPENDED');
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    expect((await request(t.token)).statusCode).toBe(200);
    const c = await makeCustomer();
    expect((await request(c.token)).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/technician/me/payout-requests' })).statusCode).toBe(401);
  });
});
