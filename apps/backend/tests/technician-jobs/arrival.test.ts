import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a fresh booking to ACCEPTED by the given technician; return its id. */
async function bookedAndAccepted(cust: { token: string; customerId: string }, tech: { token: string }, addrServ: { addressId: string; serviceId: string }) {
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(cust.token),
    payload: { addressId: addrServ.addressId, serviceId: addrServ.serviceId, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(tech.token) });
  return booking.id as string;
}

describe('arrival handshake — en-route + arrive', () => {
  it('technician goes en-route (ACCEPTED→EN_ROUTE) then arrives (GPS recorded, code minted, state unchanged)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // address has no lat/lng by default
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });

    const er = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    expect(er.statusCode).toBe(200);
    expect(er.json().state).toBe('EN_ROUTE');

    const arr = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } });
    expect(arr.statusCode).toBe(200);
    expect(arr.json().arrivalCode).toMatch(/^\d{6}$/);
    expect(arr.json().withinGeofence).toBeNull(); // address has no coords
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE'); // arrive does NOT change state
    expect(row!.arrivalLat).toBe(22.31);
  });

  it('GPS gate: with address coords, a tap >200m → 422; within → ok withinGeofence:true', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.address.update({ where: { id: f.address.id }, data: { lat: 22.3072, lng: 73.1812 } });
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });

    const far = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.40, lng: 73.30 } });
    expect(far.statusCode).toBe(422);
    // even a REJECTED (too-far) tap records the technician's GPS for fraud review (no silent retry)
    const afterFar = await prisma.booking.findUnique({ where: { id } });
    expect(afterFar!.arrivalLat).toBe(22.40);
    const near = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.3074, lng: 73.1813 } });
    expect(near.statusCode).toBe(200);
    expect(near.json().withinGeofence).toBe(true);
  });

  it('confirm-arrival is BLOCKED (422) when the recorded GPS is outside the geofence (coords added after a no-coords arrive)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // no address coords → geofence skipped at arrive
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.40, lng: 73.30 } })).json().arrivalCode as string;
    // now coords exist AND the recorded arrival GPS is far from them → withinGeofence:false at confirm
    await prisma.address.update({ where: { id: f.address.id }, data: { lat: 22.3072, lng: 73.1812 } });
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
    expect(res.statusCode).toBe(422);
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE'); // not ARRIVED — geofence enforced at confirm
    expect(row!.visitFeeLockedAt).toBeNull();
  });

  it('en-route from non-ACCEPTED → 409; arrive from non-EN_ROUTE → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    // arrive before en-route (still ACCEPTED) → 409
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).statusCode).toBe(409);
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    // en-route again from EN_ROUTE → 409
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) })).statusCode).toBe(409);
  });

  it("a different technician cannot drive en-route/arrive on someone else's accepted job → 403", async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(other.token) })).statusCode).toBe(403);
  });

  it('a CUSTOMER calling /arrive → 403; lat without lng → 400', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(c.token), payload: { lat: 22.31, lng: 73.18 } })).statusCode).toBe(403);
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31 } })).statusCode).toBe(400);
  });
});

describe('arrival handshake — customer confirm (the two-sided gate)', () => {
  async function enRouteAndArrive(c: { token: string; customerId: string }, t: { token: string }, f: { address: { id: string }; service: { id: string } }) {
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode as string;
    return { id, code };
  }

  it('correct code → ARRIVED, arrivedAt + visitFeeLockedAt set, audit has no raw coords', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id, code } = await enRouteAndArrive(c, t, f);
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('ARRIVED');
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.arrivedAt).not.toBeNull();
    expect(row!.visitFeeLockedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'ARRIVED' } } });
    expect(audit!.metadata).toMatchObject({ codeConfirmed: true });
    expect(JSON.stringify(audit!.metadata)).not.toMatch(/73\.18|22\.31/); // no raw coords
  });

  it('confirm before the technician tapped Arrived (no code) → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code: '123456' } })).statusCode).toBe(409);
  });

  it('wrong code → 401; 5 wrong attempts invalidate the code (the right code then also 401)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id, code } = await enRouteAndArrive(c, t, f);
    for (let i = 0; i < 5; i++) expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code: '000000' } })).statusCode).toBe(401);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code } })).statusCode).toBe(401);
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE'); // never reached ARRIVED
  });

  it("another customer's confirm-arrival → 404 (no IDOR); a TECHNICIAN calling it → 403", async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id, code } = await enRouteAndArrive(c, t, f);
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(other.token), payload: { code } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(t.token), payload: { code } })).statusCode).toBe(403);
  });

  it('single-party: technician arrives but customer never confirms → booking stays EN_ROUTE', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id } = await enRouteAndArrive(c, t, f);
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE');
    expect(row!.visitFeeLockedAt).toBeNull();
  });
});
