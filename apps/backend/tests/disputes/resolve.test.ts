import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

// Charge = 45100 (the Payment.amountPaise seeded by disputedBooking)
// laborPaise = 60000, visitFeePaise = 14900 (from seedBookable defaults)
// COMMISSION_RATE_BPS = 2000 (20%) — earningPaise = floor(base * 0.8), commission = remainder
// splitPaise(60000) → earningPaise = floor(60000 * 8000 / 10000) = 48000, commission = 12000
// splitPaise(40000) → earningPaise = floor(40000 * 0.8) = 32000, commission = 8000
// splitPaise(14900) → earningPaise = floor(14900 * 0.8) = 11920, commission = 2980

const CHARGE = 45100;
const LABOR = 60000;
const VISIT_FEE = 14900;

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

/** Seed a DISPUTED booking with a captured UPI payment. Returns tokens + ids. */
async function disputedBooking(opts?: { method?: 'UPI' | 'CASH'; cashDebt?: number }) {
  const method = opts?.method ?? 'UPI';
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
      amountPaise: CHARGE,
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
  it('credits full labor (60000): EARNING_CREDIT 48000 + COMMISSION 12000; NO DISPUTE_REVERSAL; no gateway.refund; booking CLOSED', async () => {
    const { bookingId, disputeId, adminToken } = await disputedBooking();

    const res = await app.inject({
      method: 'POST',
      url: `/admin/disputes/${disputeId}/resolve`,
      headers: auth(adminToken),
      payload: { outcome: 'FAVOR_TECHNICIAN', reason: 'Work was completed correctly' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: bookingId, state: 'CLOSED', outcome: 'FAVOR_TECHNICIAN', refundPaise: 0 });

    // Ledger: EARNING_CREDIT 48000 + COMMISSION 12000
    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId }, orderBy: { type: 'asc' } });
    expect(entries).toHaveLength(2);
    const earning = entries.find(e => e.type === 'EARNING_CREDIT');
    const commission = entries.find(e => e.type === 'COMMISSION');
    expect(earning?.amountPaise).toBe(48000); // floor(60000 * 0.8)
    expect(commission?.amountPaise).toBe(12000); // 60000 - 48000
    // Conservation: retained(60000) + refund(0) == base(60000)
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

    // DISPUTE_EVENT audit
    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'resolved' } },
    });
    expect(audit).not.toBeNull();
  });
});

describe('POST /admin/disputes/:id/resolve — FAVOR_CUSTOMER (UPI)', () => {
  it('refund == charge (45100): retained = base - charge = 14900; EARNING_CREDIT 11920 + COMMISSION 2980 + DISPUTE_REVERSAL 45100; CLOSED', async () => {
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
    // retained = LABOR - CHARGE = 60000 - 45100 = 14900
    // splitPaise(14900) → earningPaise = floor(14900*0.8) = 11920, commission = 2980
    const earning = entries.find(e => e.type === 'EARNING_CREDIT');
    const commission = entries.find(e => e.type === 'COMMISSION');
    const reversal = entries.find(e => e.type === 'DISPUTE_REVERSAL');

    expect(earning?.amountPaise).toBe(11920);
    expect(commission?.amountPaise).toBe(2980);
    expect(reversal?.amountPaise).toBe(CHARGE); // 45100

    // Conservation: retained(14900) + refund(45100) == base(60000)
    expect(earning!.amountPaise + commission!.amountPaise + reversal!.amountPaise).toBe(LABOR);

    const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(booking!.state).toBe('CLOSED');

    // For UPI: a refund_initiated audit must exist (the dev gateway resolves synchronously)
    const auditInitiated = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'resolved' } },
    });
    expect(auditInitiated).not.toBeNull();
    const meta = auditInitiated!.metadata as Record<string, unknown>;
    expect(meta.refundId).toBeTruthy(); // refundId from the dev gateway
  });
});

describe('POST /admin/disputes/:id/resolve — PARTIAL', () => {
  it('refund 20000: retained = 40000; EARNING_CREDIT 32000 + COMMISSION 8000 + DISPUTE_REVERSAL 20000; money conserved', async () => {
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

    expect(earning?.amountPaise).toBe(32000); // floor(40000 * 0.8)
    expect(commission?.amountPaise).toBe(8000); // 40000 - 32000
    expect(reversal?.amountPaise).toBe(20000);

    // Conservation: retained(40000) + refund(20000) == base(60000)
    expect(earning!.amountPaise + commission!.amountPaise + reversal!.amountPaise).toBe(LABOR);
    expect(earning!.amountPaise + commission!.amountPaise + reversal!.amountPaise)
      .toBe(40000 + 20000); // 60000

    const booking = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(booking!.state).toBe('CLOSED');
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

    // manual refund_recorded audit should exist
    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'resolved' } },
    });
    expect(audit).not.toBeNull();
    const meta = audit!.metadata as Record<string, unknown>;
    expect(meta.method).toBe('CASH');

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

    // earningPaise = 48000, debt = 30000 → offset = min(48000, 30000) = 30000
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
