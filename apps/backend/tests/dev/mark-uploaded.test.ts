import { randomUUID } from 'node:crypto';
import Fastify, { type FastifyInstance } from 'fastify';
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { registerDevRoutes } from '../../src/modules/dev/dev.routes.js';
import { registerErrorHandler } from '../../src/shared/middleware/errorHandler.js';
import { photoStorage, DevPhotoStorage, type PhotoStorage } from '../../src/shared/third-party/r2-storage.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }
const ROUTE = '/dev/photos/mark-uploaded';

/** Booking driven to ARRIVED (the diagnosis photo window). Mirrors tests/technician-jobs/photos.test.ts. */
async function arrivedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  return { t, bookingId: booking.id as string };
}

/** A fresh Fastify with only the error handler + the dev routes, so each guard is tested in isolation. */
async function isolatedApp(opts: { storage: PhotoStorage; nodeEnv: string }): Promise<FastifyInstance> {
  const a = Fastify({ logger: false });
  registerErrorHandler(a);
  await registerDevRoutes(a, opts);
  await a.ready();
  return a;
}

/** A real-R2-shaped storage that is NOT the Dev impl. */
const notDevStorage: PhotoStorage = {
  presignUpload: async () => ({ url: 'https://r2.example/upload', expiresAt: new Date() }),
  objectExists: async () => false,
  presignRead: async () => 'https://r2.example/read',
};

describe('POST /dev/photos/mark-uploaded (dev-only photo hook)', () => {
  it('is registered by buildApp outside production', () => {
    expect(app.hasRoute({ method: 'POST', url: ROUTE })).toBe(true);
  });

  it('authed {key} → 204, the object then exists, and a photo confirm for that key succeeds', async () => {
    const { t, bookingId } = await arrivedBooking();
    const sign = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 200_000 } })).json();
    expect(await photoStorage.objectExists(sign.key)).toBe(false);

    const res = await app.inject({ method: 'POST', url: ROUTE, headers: auth(t.token), payload: { key: sign.key } });
    expect(res.statusCode).toBe(204);
    expect(res.body).toBe('');
    expect(await photoStorage.objectExists(sign.key)).toBe(true);

    const confirm = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: sign.key, capturedAt: new Date().toISOString() } });
    expect(confirm.statusCode).toBe(201);
  });

  it('ownership (finding 8): a customer token → 403 (not a technician at all)', async () => {
    const { bookingId } = await arrivedBooking();
    const customer = await makeCustomer();
    const key = `jobs/${bookingId}/DIAGNOSIS_OVERVIEW-${randomUUID()}.jpg`;
    const res = await app.inject({ method: 'POST', url: ROUTE, headers: auth(customer.token), payload: { key } });
    expect(res.statusCode).toBe(403);
  });

  it('ownership (finding 8): a DIFFERENT technician\'s token → 403 (not assigned to them)', async () => {
    const { bookingId } = await arrivedBooking();
    const other = await makeTechnician(['AC']);
    const key = `jobs/${bookingId}/DIAGNOSIS_OVERVIEW-${randomUUID()}.jpg`;
    const res = await app.inject({ method: 'POST', url: ROUTE, headers: auth(other.token), payload: { key } });
    expect(res.statusCode).toBe(403);
    expect(res.json().message).toBe('This job is not assigned to you');
  });

  it('ownership (finding 8): a malformed key → 422', async () => {
    const { t } = await arrivedBooking();
    const res = await app.inject({ method: 'POST', url: ROUTE, headers: auth(t.token), payload: { key: 'not-a-photo-key.jpg' } });
    expect(res.statusCode).toBe(422);
    expect(res.json().message).toBe('Invalid photo key');
  });

  it('ownership (finding 8): a key for a non-existent booking → 404', async () => {
    const { t } = await arrivedBooking();
    const key = `jobs/${randomUUID()}/DIAGNOSIS_OVERVIEW-${randomUUID()}.jpg`;
    const res = await app.inject({ method: 'POST', url: ROUTE, headers: auth(t.token), payload: { key } });
    expect(res.statusCode).toBe(404);
    expect(res.json().message).toBe('Job not found');
  });

  it('no auth → 401 (and nothing is marked)', async () => {
    const key = 'jobs/b-unauthed/DIAGNOSIS_OVERVIEW-x.jpg';
    const res = await app.inject({ method: 'POST', url: ROUTE, payload: { key } });
    expect(res.statusCode).toBe(401);
    expect(await photoStorage.objectExists(key)).toBe(false);
  });

  it('invalid body → 400: missing key, empty key, non-string key, oversize key, extra field', async () => {
    const t = await makeTechnician(['AC']);
    const bad: Array<Record<string, unknown>> = [
      {},
      { key: '' },
      { key: 123 },
      { key: 'k'.repeat(513) },
      { key: 'jobs/b1/DIAGNOSIS_OVERVIEW-x.jpg', extra: true },
    ];
    for (const payload of bad) {
      const res = await app.inject({ method: 'POST', url: ROUTE, headers: auth(t.token), payload });
      expect(res.statusCode, JSON.stringify(payload)).toBe(400);
    }
  });

  it('nodeEnv production → the route is not registered at all (404 even when authed)', async () => {
    const t = await makeTechnician(['AC']);
    const prod = await isolatedApp({ storage: new DevPhotoStorage(), nodeEnv: 'production' });
    try {
      expect(prod.hasRoute({ method: 'POST', url: ROUTE })).toBe(false);
      const res = await prod.inject({ method: 'POST', url: ROUTE, headers: auth(t.token), payload: { key: 'jobs/b1/k.jpg' } });
      expect(res.statusCode).toBe(404);
    } finally {
      await prod.close();
    }
  });

  it('non-Dev storage (real R2) → 404; never fakes an upload against real storage', async () => {
    const t = await makeTechnician(['AC']);
    const realish = await isolatedApp({ storage: notDevStorage, nodeEnv: 'test' });
    try {
      const res = await realish.inject({ method: 'POST', url: ROUTE, headers: auth(t.token), payload: { key: 'jobs/b1/k.jpg' } });
      expect(res.statusCode).toBe(404);
      expect(res.json().code).toBe('NOT_FOUND');
    } finally {
      await realish.close();
    }
  });
});
