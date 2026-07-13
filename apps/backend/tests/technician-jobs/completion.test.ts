import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos, seedRepairPhotos } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a booking through BOTH keystones' prerequisites: … → REPAIR_COMPLETE. */
async function repairCompleteBooking() {
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
  return { c, t, bookingId: booking.id as string };
}

describe('completion handshake (keystone #2)', () => {
  it('E2E: customer requests the code, technician enters it → CUSTOMER_CONFIRMED + confirmedAt + audit evidence', async () => {
    const { c, t, bookingId } = await repairCompleteBooking();
    const mint = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) });
    expect(mint.statusCode).toBe(200);
    const devOtp = mint.json().devOtp as string;
    expect(devOtp).toMatch(/^\d{6}$/);
    const confirm = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: devOtp } });
    expect(confirm.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('CUSTOMER_CONFIRMED');
    expect(row!.confirmedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'CUSTOMER_CONFIRMED' } } });
    expect((audit!.metadata as { codeConfirmed: boolean }).codeConfirmed).toBe(true);
    // single-use: replaying the same code → 409 (booking moved on) not a second confirm
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(409);
  });

  it('mint guards: wrong state 409, foreign customer 404, technician-role 403, throttle 429 after 3', async () => {
    const { c, t, bookingId } = await repairCompleteBooking();
    const fresh = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(fresh.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(t.token) })).statusCode).toBe(403);
    for (let i = 0; i < 3; i++) expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).statusCode).toBe(429);
  });

  it('mint before REPAIR_COMPLETE → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/request-completion-otp`, headers: auth(c.token) })).statusCode).toBe(409);
  });

  it('verify guards: no code yet 409; wrong code 401; a re-mint replaces the old code', async () => {
    const { c, t, bookingId } = await repairCompleteBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: '000000' } })).statusCode).toBe(409); // no-code
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: '000000' } })).statusCode).toBe(401); // invalid
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: first } })).statusCode).toBe(401); // replaced
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: second } })).statusCode).toBe(200);
  });
});
