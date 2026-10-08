import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer } from '../bookings/helpers.js';
import { assignedBooking, auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const get = (token: string) => app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(token) });

describe('GET /technician/me/earnings', () => {
  it('owed comes from the ledger; net = owed − debt; limit, minimum and blocked flag reported', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [
      { type: 'EARNING_CREDIT', amountPaise: 48000 }, { type: 'COMMISSION', amountPaise: 12000 },
      { type: 'CASH_DEBT_OFFSET', amountPaise: 5000 }, { type: 'PAYOUT', amountPaise: 10000 },
    ]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 20000 } });
    const res = await get(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      owedPaise: 33000, netPayoutPaise: 13000, cashDebtPaise: 20000, cashDebtLimitPaise: 50000,
      acceptBlocked: false, payoutMinPaise: 10000, pendingPaise: 0, pending: [], latestPayoutRequest: null,
    });
  });

  it('acceptBlocked only ABOVE the limit (same rule as accept)', async () => {
    const t = await makeTechnician(['AC']);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 50000 } });
    expect((await get(t.token)).json().acceptBlocked).toBe(false);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 50001 } });
    expect((await get(t.token)).json().acceptBlocked).toBe(true);
  });

  it('net never goes below 0', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 1000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 5000 } });
    expect((await get(t.token)).json().netPayoutPaise).toBe(0);
  });

  it('pending: own PAYMENT_RECEIVED with the sweep share + release time; DISPUTED on hold; others excluded', async () => {
    const t = await makeTechnician(['AC']);
    const other = await makeTechnician(['AC']);
    const paidAt = new Date('2026-10-05T08:30:00.000Z');
    const labor = await assignedBooking(app, t.technicianId, 'PAYMENT_RECEIVED', { paidAt });
    const declined = await assignedBooking(app, t.technicianId, 'PAYMENT_RECEIVED', { paidAt, declinedAt: new Date() });
    const disputed = await assignedBooking(app, t.technicianId, 'DISPUTED', { paidAt });
    await assignedBooking(app, t.technicianId, 'CLOSED', { paidAt });
    await assignedBooking(app, other.technicianId, 'PAYMENT_RECEIVED', { paidAt });
    const body = (await get(t.token)).json();
    const byId = new Map((body.pending as Array<{ bookingId: string }>).map((p) => [p.bookingId, p]));
    expect(byId.size).toBe(3);
    expect(byId.get(labor.bookingId)).toEqual({
      bookingId: labor.bookingId, bookingNumber: labor.bookingNumber, serviceName: labor.serviceName,
      amountPaise: 48000, releasesAt: '2026-10-07T08:30:00.000Z', onHold: false,
    });
    expect(byId.get(declined.bookingId)).toMatchObject({ amountPaise: 11920, onHold: false });
    expect(byId.get(disputed.bookingId)).toMatchObject({ amountPaise: 48000, onHold: true, releasesAt: null });
    expect(body.pendingPaise).toBe(48000 + 11920);
  });

  it('reports the latest payout request (newest by createdAt)', async () => {
    const t = await makeTechnician(['AC']);
    await prisma.payoutRequest.create({ data: { technicianId: t.technicianId, amountPaise: 15000, status: 'PAID', createdAt: new Date('2026-10-01T00:00:00Z'), reviewedAt: new Date('2026-10-02T00:00:00Z') } });
    await prisma.payoutRequest.create({ data: { technicianId: t.technicianId, amountPaise: 20000, status: 'REJECTED', reviewNote: 'Bank details not confirmed', createdAt: new Date('2026-10-03T00:00:00Z'), reviewedAt: new Date('2026-10-04T00:00:00Z') } });
    expect((await get(t.token)).json().latestPayoutRequest).toEqual({
      id: expect.any(String), status: 'REJECTED', amountPaise: 20000, requestedAt: '2026-10-03T00:00:00.000Z',
      reviewedAt: '2026-10-04T00:00:00.000Z', reviewNote: 'Bank details not confirmed', paidPaise: null,
    });
  });

  it('a PAID latest request reports the linked PAYOUT amount as paidPaise', async () => {
    const t = await makeTechnician(['AC']);
    const entry = await prisma.ledgerEntry.create({ data: { technicianId: t.technicianId, type: 'PAYOUT', amountPaise: 12000 } });
    await prisma.payoutRequest.create({ data: { technicianId: t.technicianId, amountPaise: 15000, status: 'PAID', payoutEntryId: entry.id, reviewedAt: new Date() } });
    expect((await get(t.token)).json().latestPayoutRequest).toMatchObject({ status: 'PAID', amountPaise: 15000, paidPaise: 12000 });
  });

  it('works for a SUSPENDED technician; customer → 403; no token → 401', async () => {
    const t = await makeTechnician(['AC'], 'SUSPENDED');
    expect((await get(t.token)).statusCode).toBe(200);
    const c = await makeCustomer();
    expect((await get(c.token)).statusCode).toBe(403);
    expect((await app.inject({ method: 'GET', url: '/technician/me/earnings' })).statusCode).toBe(401);
  });
});
