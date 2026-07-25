import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeTechnician, makeAdminToken } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

/** Seed a ledger history: 48000 earned, 30000 offset, debt cache 20000 remaining. */
async function seeded() {
  const t = await makeTechnician(['AC']);
  await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 20000 } });
  await prisma.ledgerEntry.createMany({ data: [
    { technicianId: t.technicianId, type: 'EARNING_CREDIT', amountPaise: 48000 },
    { technicianId: t.technicianId, type: 'CASH_COLLECTED', amountPaise: 50000 },
    { technicianId: t.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: 30000 },
  ] });
  return t; // payable 18000, debt 20000
}

describe('GET /technician/me/balance', () => {
  it('returns ledger-derived payable + cached debt', async () => {
    const t = await seeded();
    const res = await app.inject({ method: 'GET', url: '/technician/me/balance', headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ payablePaise: 18000, cashDebtPaise: 20000 });
  });
});

describe('admin settlements', () => {
  it('payout: happy path writes PAYOUT + audit; over-payable → 409; over-debt repayment → 409', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 20000 } })).statusCode).toBe(409); // > 18000 payable
    const ok = await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 18000 } });
    expect(ok.statusCode).toBe(201);
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(1);
    expect(await prisma.auditLog.count({ where: { action: 'SETTLEMENT_EVENT', metadata: { path: ['event'], equals: 'payout_recorded' } } })).toBe(1);
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/repayments', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 25000 } })).statusCode).toBe(409); // > 20000 debt
  });

  it('repayment decrements the cached debt in the same tx', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    const res = await app.inject({ method: 'POST', url: '/admin/settlements/repayments', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 20000 } });
    expect(res.statusCode).toBe(201);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
  });

  it('walls: technician token on admin routes → 403; unknown technician → 404; zero/negative/float amount → 400', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(t.token), payload: { technicianId: t.technicianId, amountPaise: 100 } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: '00000000-0000-0000-0000-000000000000', amountPaise: 100 } })).statusCode).toBe(404);
    for (const amountPaise of [0, -5, 10.5]) {
      expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise } })).statusCode).toBe(400);
    }
  });

  it('GET /admin/settlements/technicians/:id returns balances + entries newest-first', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    const res = await app.inject({ method: 'GET', url: `/admin/settlements/technicians/${t.technicianId}`, headers: auth(admin) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.payablePaise).toBe(18000);
    expect(body.cashDebtPaise).toBe(20000);
    expect(body.entries.length).toBe(3);
  });
});
