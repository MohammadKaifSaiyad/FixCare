import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos, seedRepairPhotos } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a booking through BOTH keystones to CUSTOMER_CONFIRMED. labor 60000, visitFee 14900. */
export async function confirmedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id);
  const issue = await seedIssue(f.cat.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/approve`, headers: auth(c.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/start-repair`, headers: auth(t.token) });
  await seedRepairPhotos(booking.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/complete-repair`, headers: auth(t.token) });
  const otp = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: otp } });
  return { c, t, bookingId: booking.id as string };
}

describe('POST /me/bookings/:id/pay', () => {
  it('creates the order for the approved total (empty cart: labor − visitFee) + Payment row + audit', async () => {
    const { c, bookingId } = await confirmedBooking();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.amountPaise).toBe(45100); // 60000 − 14900, the invariant-locked approved total
    expect(body.orderId).toMatch(/^order_dev_/);
    const rows = await prisma.payment.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]!.status).toBe('CREATED');
    expect(rows[0]!.amountPaise).toBe(45100);
    expect(await prisma.auditLog.count({ where: { action: 'PAYMENT_EVENT' } })).toBe(1);
  });

  it('is idempotent: a second pay returns the SAME order (no duplicate rows)', async () => {
    const { c, bookingId } = await confirmedBooking();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect(second.orderId).toBe(first.orderId);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(1);
  });

  it('a DECLINED booking pays exactly the locked visit fee', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
    const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
    await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
    await seedDiagnosisPhotos(booking.id);
    const issue = await seedIssue(f.cat.id);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/decline`, headers: auth(c.token) });
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().amountPaise).toBe(14900); // visitFeePaise only
  });

  it('guards: wrong state 409, foreign customer 404, technician 403', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).statusCode).toBe(409);
    const confirmed = await confirmedBooking();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${confirmed.bookingId}/pay`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${confirmed.bookingId}/pay`, headers: auth(confirmed.t.token) })).statusCode).toBe(403);
  });
});
