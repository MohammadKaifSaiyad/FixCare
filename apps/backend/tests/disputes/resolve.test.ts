import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

// Charge = 45100 (Payment.amountPaise seeded by disputedBooking = labor 60000 − visitFee 14900, no parts).
// Technician earning base is LABOR (parts are the merchant's, never split to the tech), PRORATED by the
// fraction of the charge the customer retained: retainedLabor = round(labor × (charge − refund) / charge),
// then splitPaise (earning = floor(retainedLabor × 0.8), commission = remainder). Customer refund is
// bounded by the full charge and recorded as DISPUTE_REVERSAL.
//   FAVOR_TECHNICIAN: refund 0     → retainedLabor 60000 → earning 48000, commission 12000 (== the B6c sweep)
//   FAVOR_CUSTOMER:   refund 45100 → retainedLabor 0     → NO earning/commission, DISPUTE_REVERSAL 45100
//   PARTIAL:          refund 20000 → retainedLabor round(60000×25100/45100)=33392 → earning floor(33392×0.8)=26713, commission 6679
// (Parts money is never credited to the technician — verified by a with-parts test below.)

const CHARGE = 45100;
const LABOR = 60000;
const VISIT_FEE = 14900;

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

/** Seed a DISPUTED booking with a captured UPI payment. Returns tokens + ids.
 *  chargePaise overrides the captured amount (default CHARGE = labor−visitFee, no parts); pass a
 *  higher value to simulate a booking WITH parts (labor + parts − visitFee). */
async function disputedBooking(opts?: { method?: 'UPI' | 'CASH'; cashDebt?: number; chargePaise?: number }) {
  const method = opts?.method ?? 'UPI';
  const chargePaise = opts?.chargePaise ?? CHARGE;
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const b = await prisma.booking.create({
    data: {
      customerId: c.customerId,
      bookingNumber: `FC-DISP-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      state: 'DISPUTED',
      scheduledSlot: new Date(),
      serviceId: f.service.id,
      serviceName: f.service.name,
      zoneId: f.zone.id,
      zoneName: f.zoneName,
      addressId: f.address.id,
      laborPaise: f.laborPaise,
      visitFeePaise: f.visitFeePaise,
      laborTier: 'T2',
      technicianId: t.technicianId,
      paidAt: new Date(),
    },
  });
  const payment = await prisma.payment.create({
    data: {
      bookingId: b.id,
      method,
      status: 'CAPTURED',
      amountPaise: chargePaise,
      capturedAt: new Date(),
      razorpayOrderId: method === 'UPI' ? `order_dev_${Math.random().toString(36).slice(2, 8)}` : null,
      razorpayPaymentId: method === 'UPI' ? `pay_dev_${Math.random().toString(36).slice(2, 8)}` : null,
    },
  });
  const dispute = await prisma.dispute.create({
    data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'AC not cooling', status: 'OPEN' },
  });
  if (opts?.cashDebt && opts.cashDebt > 0) {
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: opts.cashDebt } });
  }
  const adminToken = await makeAdminToken();
  return { c, t, bookingId: b.id as string, disputeId: dispute.id as string, payment, adminToken };
}

describe('POST /admin/disputes/:id/resolve — FAVOR_TECHNICIAN', () => {
  it('refund 0 → retains full labor (60000): EARNING_CREDIT 48000 + COMMISSION 12000 (== the sweep); NO DISPUTE_REVERSAL; no gateway.refund; booking CLOSED', async () => {
    const { bookingId, disputeId, adminToken } = await disputedBooking();

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Work was completed correctly' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: bookingId, state: 'CLOSED', outcome: 'FAVOR_TECHNICIAN', refundPaise: 0 });

    // retainedLabor = round(60000 × 45100/45100) = 60000 → split 48000/12000, IDENTICAL to a normal
    // sweep close (a technician who wins their dispute is not penalized).
    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId }, orderBy: { type: 'asc' } });
    expect(entries).toHaveLength(2);
    const earning = entries.find(e => e.type === 'EARNING_CREDIT');
    const commission = entries.find(e => e.type === 'COMMISSION');
    expect(earning?.amountPaise).toBe(48000);
    expect(commission?.amountPaise).toBe(12000);
    expect(earning!.amountPaise + commission!.amountPaise).toBe(LABOR);

    // No DISPUTE_REVERSAL
    expect(entries.find(e => e.type === 'DISPUTE_REVERSAL')).toBeUndefined();

    // Booking CLOSED
    const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(booking!.state).toBe('CLOSED');
    expect(booking!.closedAt).not.toBeNull();

    // Dispute RESOLVED
    const dispute = await prisma.dispute.findFirst({ where: { bookingId } });
    expect(dispute!.status).toBe('RESOLVED');
    expect(dispute!.outcome).toBe('FAVOR_TECHNICIAN');

    // DISPUTE_EVENT audit carries the admin's rationale (adminReason)
    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'resolved' } },
    });
    expect(audit).not.toBeNull();
    expect((audit!.metadata as Record<string, unknown>).adminReason).toBe('Work was completed correctly');
  });
});

describe('POST /admin/disputes/:id/resolve — FAVOR_CUSTOMER (UPI)', () => {
  it('refund == charge (45100): technician at fault → retained 0 → NO earning/commission, only DISPUTE_REVERSAL 45100; CLOSED', async () => {
    const { bookingId, disputeId, adminToken } = await disputedBooking();

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_CUSTOMER', refundPaise: CHARGE, reason: 'Technician was at fault' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: bookingId, state: 'CLOSED', outcome: 'FAVOR_CUSTOMER', refundPaise: CHARGE });

    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId }, orderBy: { type: 'asc' } });
    // retained = charge − refund = 45100 − 45100 = 0 → the technician is credited NOTHING
    // (at fault → deduct from payout, per dispute-resolution.md). Only the reversal is written.
    expect(entries.find(e => e.type === 'EARNING_CREDIT')).toBeUndefined();
    expect(entries.find(e => e.type === 'COMMISSION')).toBeUndefined();
    const reversal = entries.find(e => e.type === 'DISPUTE_REVERSAL');
    expect(reversal?.amountPaise).toBe(CHARGE); // 45100
    // Conservation: retained(0) + refund(45100) == charge(45100)
    expect(reversal!.amountPaise).toBe(CHARGE);

    const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(booking!.state).toBe('CLOSED');

    // UPI: the resolved audit carries the dev-gateway refundId
    const auditInitiated = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'resolved' } },
    });
    expect(auditInitiated).not.toBeNull();
    expect((auditInitiated!.metadata as Record<string, unknown>).refundId).toBeTruthy();
  });
});

describe('POST /admin/disputes/:id/resolve — PARTIAL', () => {
  it('refund 20000: retainedLabor = round(60000×25100/45100)=33392 → EARNING 26713 + COMMISSION 6679 + DISPUTE_REVERSAL 20000', async () => {
    const { bookingId, disputeId, adminToken } = await disputedBooking();

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'PARTIAL', refundPaise: 20000, reason: 'Partial work was done' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: bookingId, state: 'CLOSED', outcome: 'PARTIAL', refundPaise: 20000 });

    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId } });
    const earning = entries.find(e => e.type === 'EARNING_CREDIT');
    const commission = entries.find(e => e.type === 'COMMISSION');
    const reversal = entries.find(e => e.type === 'DISPUTE_REVERSAL');

    // retainedLabor = round(60000 × (45100−20000)/45100) = round(33392.46) = 33392
    // splitPaise(33392) → floor(33392×0.8)=26713, commission 33392−26713=6679
    expect(earning?.amountPaise).toBe(26713);
    expect(commission?.amountPaise).toBe(6679);
    expect(reversal?.amountPaise).toBe(20000);
    // earning + commission == retainedLabor (labor share); the reversal is the customer refund.
    expect(earning!.amountPaise + commission!.amountPaise).toBe(33392);

    const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(booking!.state).toBe('CLOSED');
  });
});

describe('POST /admin/disputes/:id/resolve — WITH PARTS (parts money never credited to the technician)', () => {
  it('FAVOR_TECHNICIAN on a parts booking: earning derives from LABOR only, not the parts-inflated charge', async () => {
    // labor 60000, parts 30000, visitFee credit 14900 → captured charge = 90000 − 14900 = 75100.
    // The technician must earn splitPaise(labor 60000) = 48000, NOT splitPaise(charge 75100) = 60080
    // (the 12080 difference is the merchant's parts money — Golden Rule 4 / pricing-model.md).
    const CHARGE_WITH_PARTS = 75100;
    const { bookingId, disputeId, adminToken } = await disputedBooking({ chargePaise: CHARGE_WITH_PARTS });

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Work verified' },
    });
    expect(res.statusCode).toBe(200);

    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId } });
    const earning = entries.find(e => e.type === 'EARNING_CREDIT');
    const commission = entries.find(e => e.type === 'COMMISSION');
    // retainedLabor = round(60000 × 75100/75100) = 60000 → 48000/12000. NOT 60080 (the parts-over-credit bug).
    expect(earning?.amountPaise).toBe(48000);
    expect(commission?.amountPaise).toBe(12000);
    expect(earning!.amountPaise + commission!.amountPaise).toBe(LABOR); // == labor, parts excluded
  });

  it('FAVOR_CUSTOMER on a parts booking: reversal is the FULL charge (parts included) but the technician earns 0', async () => {
    const CHARGE_WITH_PARTS = 75100;
    const { bookingId, disputeId, adminToken } = await disputedBooking({ chargePaise: CHARGE_WITH_PARTS });

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_CUSTOMER', refundPaise: CHARGE_WITH_PARTS, reason: 'At fault' },
    });
    expect(res.statusCode).toBe(200);

    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId } });
    expect(entries.find(e => e.type === 'EARNING_CREDIT')).toBeUndefined();
    expect(entries.find(e => e.type === 'COMMISSION')).toBeUndefined();
    // Customer is refunded the full charge (labor + parts − credit); technician deducted entirely.
    expect(entries.find(e => e.type === 'DISPUTE_REVERSAL')?.amountPaise).toBe(CHARGE_WITH_PARTS);
  });
});

describe('POST /admin/disputes/:id/resolve — cash booking', () => {
  it('cash booking: no gateway.refund called; DISPUTE_REVERSAL still written; booking CLOSED', async () => {
    const { bookingId, disputeId, adminToken, payment } = await disputedBooking({ method: 'CASH' });

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'PARTIAL', refundPaise: 20000, reason: 'Partial cash refund' },
    });
    expect(res.statusCode).toBe(200);

    // DISPUTE_REVERSAL must still be written for cash
    const reversal = await prisma.ledgerEntry.findFirst({ where: { bookingId, type: 'DISPUTE_REVERSAL' } });
    expect(reversal?.amountPaise).toBe(20000);

    // Payment razorpayRefundId must remain null (no gateway call)
    const p = await prisma.payment.findUnique({ where: { id: payment.id } });
    expect(p!.razorpayRefundId).toBeNull();

    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'resolved' } },
    });
    expect(audit).not.toBeNull();
    const meta = audit!.metadata as Record<string, unknown>;
    expect(meta.method).toBe('CASH');

    // A cash refund has no gateway confirmation → a distinct marker must flag that ops still has to
    // physically pay the customer back (the ledger recorded the money leaving; for cash it hasn't).
    const manual = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'manual_refund_recorded' } },
    });
    expect(manual).not.toBeNull();
    expect((manual!.metadata as { refundPaise: number }).refundPaise).toBe(20000);

    const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(booking!.state).toBe('CLOSED');
  });
});

describe('POST /admin/disputes/:id/resolve — auto-offset cash debt', () => {
  it('offsets cash debt against credited earning (B6c idiom): cashDebt reduced, CASH_DEBT_OFFSET entry created', async () => {
    const cashDebt = 30000;
    const { bookingId, disputeId, adminToken, t } = await disputedBooking({ cashDebt });

    await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Work verified' },
    });

    // FAVOR_TECHNICIAN retains full labor → earning 48000, debt 30000 → offset = min(48000, 30000) = 30000
    const offsetEntry = await prisma.ledgerEntry.findFirst({ where: { bookingId, type: 'CASH_DEBT_OFFSET' } });
    expect(offsetEntry?.amountPaise).toBe(30000);

    // Technician.cashDebtPaise decremented to 0
    const tech = await prisma.technician.findUnique({ where: { id: t.technicianId } });
    expect(tech!.cashDebtPaise).toBe(0);
  });

  it('no cash debt: no CASH_DEBT_OFFSET entry created', async () => {
    const { bookingId, disputeId, adminToken } = await disputedBooking();

    await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Work verified' },
    });

    const offsetEntry = await prisma.ledgerEntry.findFirst({ where: { bookingId, type: 'CASH_DEBT_OFFSET' } });
    expect(offsetEntry).toBeNull();
  });
});

describe('POST /admin/disputes/:id/resolve — validation errors', () => {
  it('refund > charge → 422', async () => {
    const { disputeId, adminToken } = await disputedBooking();
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'PARTIAL', refundPaise: CHARGE + 1, reason: 'Too much refund' },
    });
    expect(res.statusCode).toBe(422);
  });

  it('refund on FAVOR_TECHNICIAN → 422', async () => {
    const { disputeId, adminToken } = await disputedBooking();
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', refundPaise: 1000, reason: 'No refund expected' },
    });
    expect(res.statusCode).toBe(422);
  });

  it('missing refundPaise on PARTIAL → 422', async () => {
    const { disputeId, adminToken } = await disputedBooking();
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'PARTIAL', reason: 'Missing refund amount' },
    });
    expect(res.statusCode).toBe(422);
  });

  it('FAVOR_CUSTOMER with wrong refundPaise (not == charge) → 422', async () => {
    const { disputeId, adminToken } = await disputedBooking();
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_CUSTOMER', refundPaise: CHARGE - 1, reason: 'Wrong amount' },
    });
    expect(res.statusCode).toBe(422);
  });

  it('missing reason → 400', async () => {
    const { disputeId, adminToken } = await disputedBooking();
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN' },
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('POST /admin/disputes/:id/resolve — state guards', () => {
  it('already-RESOLVED dispute → 409', async () => {
    const { disputeId, adminToken } = await disputedBooking();

    // First resolve
    await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'First resolution' },
    });

    // Second resolve attempt
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Second attempt' },
    });
    expect(res.statusCode).toBe(409);
  });

  it('non-existent dispute → 404', async () => {
    const adminToken = await makeAdminToken();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/disputes/00000000-0000-0000-0000-000000000000/resolve',
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Ghost' },
    });
    expect(res.statusCode).toBe(404);
  });

  it('CONCURRENT resolves: exactly ONE succeeds, the other 409s — no double-refund, one set of ledger rows', async () => {
    const { disputeId, adminToken } = await disputedBooking({ method: 'UPI' });
    // Two admins (or a double-submit) hit resolve at once. The atomic OPEN→RESOLVED claim gates
    // the gateway refund: only one call gets past it, so the refund fires exactly once.
    const [a, b] = await Promise.all([
      app.inject({ method: 'POST', url: `/admin/disputes/${disputeId}/resolve`, headers: auth(adminToken), payload: { outcome: 'FAVOR_CUSTOMER', refundPaise: CHARGE, reason: 'race a' } }),
      app.inject({ method: 'POST', url: `/admin/disputes/${disputeId}/resolve`, headers: auth(adminToken), payload: { outcome: 'FAVOR_CUSTOMER', refundPaise: CHARGE, reason: 'race b' } }),
    ]);
    const codes = [a.statusCode, b.statusCode].sort();
    expect(codes).toEqual([200, 409]); // exactly one wins
    const booking = await prisma.dispute.findUnique({ where: { id: disputeId } });
    // exactly one reversal entry for the one booking (no double-refund ledger trail)
    expect(await prisma.ledgerEntry.count({ where: { bookingId: booking!.bookingId, type: 'DISPUTE_REVERSAL' } })).toBe(1);
  });
});

describe('POST /admin/disputes/:id/resolve — RBAC', () => {
  it('non-admin (technician token) → 403', async () => {
    const { disputeId } = await disputedBooking();
    const t = await makeTechnician(['AC']);
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(t.token),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Not allowed' },
    });
    expect(res.statusCode).toBe(403);
  });

  it('non-admin (customer token) → 403', async () => {
    const { disputeId, c } = await disputedBooking();
    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(c.token),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Customer trying to resolve' },
    });
    expect(res.statusCode).toBe(403);
  });
});

describe('GET /admin/disputes/:id', () => {
  it('returns the dispute case file with booking id and dispute fields', async () => {
    const { bookingId, disputeId, adminToken } = await disputedBooking();

    const res = await app.inject({
      method: 'GET',
      url: `/admin/disputes/${disputeId}`,
      headers: auth(adminToken),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.id).toBe(disputeId);
    expect(body.bookingId).toBe(bookingId);
    expect(body.status).toBe('OPEN');
    expect(body.outcome).toBeNull();
    // Admin case-file surfaces the complaint text (admin needs it to adjudicate; this route is
    // MANAGER-gated). The CUSTOMER-facing BookingDto.dispute still omits reason.
    expect(body.reason).toBe('AC not cooling');
    // No raw user objects — just structured DTO
    expect(body.raisedByUserId).toBeUndefined();
  });

  it('non-existent → 404', async () => {
    const adminToken = await makeAdminToken();
    const res = await app.inject({
      method: 'GET',
      url: '/admin/disputes/00000000-0000-0000-0000-000000000000',
      headers: auth(adminToken),
    });
    expect(res.statusCode).toBe(404);
  });
});

describe('GET /admin/disputes', () => {
  it('lists OPEN disputes (status=OPEN filter)', async () => {
    const d1 = await disputedBooking();
    const d2 = await disputedBooking();
    // Resolve d1
    await app.inject({
      method: 'POST',
      url: `/admin/disputes/${d1.disputeId}/resolve`,
      headers: auth(d1.adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Resolved' },
    });

    const adminToken = await makeAdminToken();
    const res = await app.inject({
      method: 'GET',
      url: '/admin/disputes?status=OPEN',
      headers: auth(adminToken),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(Array.isArray(body.disputes)).toBe(true);
    expect(body.disputes.length).toBe(1);
    expect(body.disputes[0].id).toBe(d2.disputeId);
  });

  it('lists all disputes (no filter)', async () => {
    const d1 = await disputedBooking();
    const d2 = await disputedBooking();
    // Resolve d1
    await app.inject({
      method: 'POST',
      url: `/admin/disputes/${d1.disputeId}/resolve`,
      headers: auth(d1.adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Resolved' },
    });

    const adminToken = await makeAdminToken();
    const res = await app.inject({
      method: 'GET',
      url: '/admin/disputes',
      headers: auth(adminToken),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.disputes.length).toBe(2);
  });

  it('invalid status query → 400', async () => {
    const adminToken = await makeAdminToken();
    const res = await app.inject({
      method: 'GET',
      url: '/admin/disputes?status=INVALID',
      headers: auth(adminToken),
    });
    expect(res.statusCode).toBe(400);
  });
});
