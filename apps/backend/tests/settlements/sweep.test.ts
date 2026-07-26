import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';
import { settleClosableBookings, splitPaise, payableBalancePaise, debtBalancePaise } from '../../src/modules/settlements/settlements.service.js';

// The sweep is a plain function — tested directly, no BullMQ, no timers. App only for fixtures.
const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }
const H49 = 49 * 3600_000;

/** Direct-seed a PAYMENT_RECEIVED booking paid `paidAgoMs` ago. labor 60000, visitFee 14900. */
async function paidBooking(opts?: { paidAgoMs?: number; declined?: boolean; cashDebtPaise?: number; method?: 'UPI' | 'CASH'; laborPaise?: number }) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  if (opts?.cashDebtPaise) await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: opts.cashDebtPaise } });
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({
    where: { id: booking.id },
    data: {
      state: 'PAYMENT_RECEIVED', technicianId: t.technicianId,
      paidAt: new Date(Date.now() - (opts?.paidAgoMs ?? H49)),
      ...(opts?.declined ? { declinedAt: new Date() } : {}),
      ...(opts?.laborPaise != null ? { laborPaise: opts.laborPaise } : {}),
    },
  });
  await prisma.payment.create({ data: { bookingId: booking.id, method: opts?.method ?? 'UPI', status: 'CAPTURED', amountPaise: 45100, capturedAt: new Date(), ...(opts?.method !== 'CASH' ? { razorpayOrderId: `order_dev_swp_${Math.random().toString(36).slice(2, 8)}` } : {}) } });
  return { c, t, bookingId: booking.id as string };
}

describe('splitPaise', () => {
  it('floors the earning; earning + commission always equals base exactly', () => {
    expect(splitPaise(60000)).toEqual({ earningPaise: 48000, commissionPaise: 12000 });
    expect(splitPaise(14900)).toEqual({ earningPaise: 11920, commissionPaise: 2980 });
    const odd = splitPaise(99);
    expect(odd.earningPaise + odd.commissionPaise).toBe(99); // 79 + 20
  });
});

describe('settleClosableBookings', () => {
  it('closes a booking paid >48h ago: CLOSED + closedAt + EARNING_CREDIT(80% labor) + COMMISSION + audit', async () => {
    const { t, bookingId } = await paidBooking();
    const r = await settleClosableBookings();
    expect(r.closed).toBe(1);
    const b = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(b!.state).toBe('CLOSED');
    expect(b!.closedAt).not.toBeNull();
    // Assert by type, not by row order — enum sort order is not a contract to depend on.
    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId } });
    const byType = new Map(entries.map((e) => [e.type, e]));
    expect(byType.get('EARNING_CREDIT')!.amountPaise).toBe(48000);
    expect(byType.get('COMMISSION')!.amountPaise).toBe(12000);
    expect((byType.get('EARNING_CREDIT')!.metadata as { rateBps: number }).rateBps).toBe(2000);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(48000);
    expect(await prisma.auditLog.count({ where: { action: 'SETTLEMENT_EVENT' } })).toBe(1);
  });

  it('a DECLINED booking earns 80% of the VISIT FEE, not labor', async () => {
    const { t } = await paidBooking({ declined: true });
    await settleClosableBookings();
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(11920); // floor(14900 × 0.8)
  });

  it('closes at EXACTLY 48h (inclusive lte cutoff); a booking 47h old stays open', async () => {
    await paidBooking({ paidAgoMs: 47 * 3600_000 }); // inside the window — stays open
    await paidBooking({ paidAgoMs: 48 * 3600_000 }); // paidAt <= (now − 48h) is true at the boundary — CLOSES
    const r = await settleClosableBookings();
    expect(r.closed).toBe(1);
  });

  it('a zero-payable booking CLOSEs but writes NO zero-amount ledger rows (amountPaise stays positive)', async () => {
    // labor 0 → split is {0,0}; the always-positive invariant means no EARNING_CREDIT/COMMISSION row.
    const { t, bookingId } = await paidBooking({ laborPaise: 0 });
    const r = await settleClosableBookings();
    expect(r.closed).toBe(1);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CLOSED');
    expect(await prisma.ledgerEntry.count({ where: { bookingId } })).toBe(0);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(0);
  });

  it('auto-offsets cash debt: earning > debt → debt 0, remainder payable; ledger shows the pairing', async () => {
    const { t } = await paidBooking({ cashDebtPaise: 30000 });
    await settleClosableBookings();
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(18000); // 48000 − 30000
    const offset = await prisma.ledgerEntry.findFirst({ where: { type: 'CASH_DEBT_OFFSET' } });
    expect(offset!.amountPaise).toBe(30000);
  });

  it('earning < debt → debt reduced, payable 0; zero debt → NO offset entry', async () => {
    const a = await paidBooking({ cashDebtPaise: 50000 });
    await settleClosableBookings();
    expect((await prisma.technician.findUnique({ where: { id: a.t.technicianId } }))!.cashDebtPaise).toBe(2000); // 50000 − 48000
    expect(await payableBalancePaise(prisma, a.t.technicianId)).toBe(0);
    await resetDb();
    const b = await paidBooking();
    await settleClosableBookings();
    expect(await prisma.ledgerEntry.count({ where: { type: 'CASH_DEBT_OFFSET' } })).toBe(0);
    expect(await debtBalancePaise(prisma, b.t.technicianId)).toBe(0);
  });

  it('is idempotent: a second run writes NOTHING', async () => {
    await paidBooking();
    await settleClosableBookings();
    const before = await prisma.ledgerEntry.count();
    const r2 = await settleClosableBookings();
    expect(r2.closed).toBe(0);
    expect(await prisma.ledgerEntry.count()).toBe(before);
  });

  it('marks stale CASH CREATED attempts FAILED at close (B6b orphan cleanup)', async () => {
    const { bookingId } = await paidBooking();
    await prisma.payment.create({ data: { bookingId, method: 'CASH', status: 'CREATED', amountPaise: 45100 } });
    await settleClosableBookings();
    const stale = await prisma.payment.findFirst({ where: { bookingId, method: 'CASH' } });
    expect(stale!.status).toBe('FAILED');
    expect(stale!.failureReason).toBe('superseded_at_close');
  });
});
