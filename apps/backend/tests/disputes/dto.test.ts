import type { DisputeOutcome, DisputeStatus } from '@prisma/client';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

const REASON = 'AC not cooling and technician left early';

interface DisputeOverrides {
  status?: DisputeStatus;
  outcome?: DisputeOutcome;
  refundPaise?: number;
  resolvedByUserId?: string;
  resolvedAt?: Date;
}

/** Seed a DISPUTED booking with a Dispute row in the given state. Mirrors resolve.test.ts's
 *  disputedBooking fixture (own copy — dto.test.ts should not depend on another test file's helper). */
async function disputedBooking(disputeOverrides?: DisputeOverrides) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const b = await prisma.booking.create({
    data: {
      customerId: c.customerId,
      bookingNumber: `FC-DTO-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
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
  const dispute = await prisma.dispute.create({
    data: { bookingId: b.id, raisedByUserId: c.userId, reason: REASON, status: 'OPEN', ...disputeOverrides },
  });
  return { c, t, bookingId: b.id as string, disputeId: dispute.id as string };
}

describe('BookingDto.dispute', () => {
  it('GET /me/bookings/:id shows an OPEN dispute with null outcome/refundPaise, no reason', async () => {
    const { c, bookingId } = await disputedBooking();
    const res = await app.inject({ method: 'GET', url: `/me/bookings/${bookingId}`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const dto = res.json();
    expect(dto.dispute).toEqual({ status: 'OPEN', outcome: null, refundPaise: null });
    expect(JSON.stringify(dto.dispute)).not.toContain(REASON);
  });

  it('GET /me/bookings/:id shows a RESOLVED dispute with outcome + refundPaise, no reason', async () => {
    const { c, bookingId } = await disputedBooking({
      status: 'RESOLVED',
      outcome: 'PARTIAL',
      refundPaise: 20000,
      resolvedByUserId: 'admin-1',
      resolvedAt: new Date(),
    });
    const res = await app.inject({ method: 'GET', url: `/me/bookings/${bookingId}`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const dto = res.json();
    expect(dto.dispute).toEqual({ status: 'RESOLVED', outcome: 'PARTIAL', refundPaise: 20000 });
    expect(JSON.stringify(dto.dispute)).not.toContain(REASON);
  });

  it('GET /me/bookings (list) includes the same dispute summary', async () => {
    const { c, bookingId } = await disputedBooking({ status: 'RESOLVED', outcome: 'FAVOR_CUSTOMER', refundPaise: 45100 });
    const res = await app.inject({ method: 'GET', url: '/me/bookings', headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const list = res.json();
    const dto = list.find((b: { id: string }) => b.id === bookingId);
    expect(dto.dispute).toEqual({ status: 'RESOLVED', outcome: 'FAVOR_CUSTOMER', refundPaise: 45100 });
    expect(JSON.stringify(dto.dispute)).not.toContain(REASON);
  });

  it('a booking with no dispute shows dispute: null', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const created = (await app.inject({
      method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: new Date(Date.now() + 86_400_000).toISOString() },
    })).json();
    const res = await app.inject({ method: 'GET', url: `/me/bookings/${created.id}`, headers: auth(c.token) });
    expect(res.json().dispute).toBeNull();
  });

  it('only the LATEST dispute is shown when a booking has more than one', async () => {
    const { c, bookingId, disputeId: first } = await disputedBooking({ status: 'RESOLVED', outcome: 'FAVOR_TECHNICIAN', refundPaise: 0 });
    // second, newer dispute — OPEN
    await prisma.dispute.create({
      data: { bookingId, raisedByUserId: c.userId, reason: 'Second issue', status: 'OPEN', createdAt: new Date(Date.now() + 1000) },
    });
    const res = await app.inject({ method: 'GET', url: `/me/bookings/${bookingId}`, headers: auth(c.token) });
    const dto = res.json();
    expect(dto.dispute).toEqual({ status: 'OPEN', outcome: null, refundPaise: null });
    expect(dto.dispute).not.toMatchObject({ status: 'RESOLVED' });
    void first;
  });
});
