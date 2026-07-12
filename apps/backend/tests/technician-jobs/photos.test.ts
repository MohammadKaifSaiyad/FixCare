import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue } from '../bookings/helpers.js';
import { photoStorage, DevPhotoStorage } from '../../src/shared/third-party/r2-storage.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }
const dev = photoStorage as DevPhotoStorage;

/** Booking driven to ARRIVED (photo window). Mirrors tests/bookings/diagnosis.test.ts. */
async function arrivedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  return { c, t, bookingId: booking.id as string };
}

/** sign + fake-PUT + confirm one slot; returns the confirm response. */
async function uploadPhoto(token: string, bookingId: string, kind: string, extra: Record<string, unknown> = {}) {
  const sign = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(token), payload: { kind, contentLengthBytes: 200_000 } })).json();
  dev.markUploaded(sign.key);
  return app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(token), payload: { kind, key: sign.key, capturedAt: new Date().toISOString(), ...extra } });
}

describe('photo sign + confirm', () => {
  it('sign returns a presigned URL + booking-scoped key; confirm creates the row + audit', async () => {
    const { t, bookingId } = await arrivedBooking();
    const sign = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 200_000 } });
    expect(sign.statusCode).toBe(200);
    const body = sign.json();
    expect(body.key.startsWith(`jobs/${bookingId}/DIAGNOSIS_OVERVIEW-`)).toBe(true);
    expect(body.url).toContain('upload');

    dev.markUploaded(body.key);
    const confirm = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: body.key, capturedAt: new Date().toISOString(), geotagLat: 22.31, geotagLng: 73.18 } });
    expect(confirm.statusCode).toBe(201);
    const rows = await prisma.photoEvidence.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]!.geotagLat).toBe(22.31);
    const audits = await prisma.auditLog.findMany({ where: { action: 'PHOTO_UPLOADED' } });
    expect(audits).toHaveLength(1);
    const meta = audits[0]!.metadata as { hasGeotag: boolean; kind: string };
    expect(meta.hasGeotag).toBe(true);
    expect(meta.kind).toBe('DIAGNOSIS_OVERVIEW');
  });

  it('confirm without a real upload → 422; key from another booking → 422', async () => {
    const { t, bookingId } = await arrivedBooking();
    const sign = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).json();
    // no markUploaded — the object does not exist
    const notUploaded = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: sign.key, capturedAt: new Date().toISOString() } });
    expect(notUploaded.statusCode).toBe(422);
    const foreignKey = 'jobs/some-other-booking/DIAGNOSIS_OVERVIEW-x.jpg';
    dev.markUploaded(foreignKey);
    const crossBooking = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: foreignKey, capturedAt: new Date().toISOString() } });
    expect(crossBooking.statusCode).toBe(422);
  });

  it('retake replaces: old row soft-deleted, audit says replaced', async () => {
    const { t, bookingId } = await arrivedBooking();
    expect((await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP')).statusCode).toBe(201);
    expect((await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP')).statusCode).toBe(201);
    expect(await prisma.photoEvidence.count({ where: { bookingId, kind: 'DIAGNOSIS_CLOSEUP' } })).toBe(2);
    expect(await prisma.photoEvidence.count({ where: { bookingId, kind: 'DIAGNOSIS_CLOSEUP', deletedAt: null } })).toBe(1);
    const audits = await prisma.auditLog.findMany({ where: { action: 'PHOTO_UPLOADED' }, orderBy: { createdAt: 'asc' } });
    expect((audits[1]!.metadata as { replaced: boolean }).replaced).toBe(true);
  });

  it('validation: bad kind 400; oversize 400; geotag lat-without-lng 400; wrong state 409; foreign tech 403', async () => {
    const { c, t, bookingId } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'SELFIE', contentLengthBytes: 1000 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 2_000_000 } })).statusCode).toBe(400);
    expect((await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW', { geotagLat: 22.3 })).statusCode).toBe(400);
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(other.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(c.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(403);
    // wrong state: cancel then try to sign → 409
    const fresh = await arrivedBooking();
    await prisma.booking.update({ where: { id: fresh.bookingId }, data: { state: 'CUSTOMER_APPROVED' } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${fresh.bookingId}/photos/sign`, headers: auth(fresh.t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(409);
  });
});

describe('diagnosis photo gate', () => {
  it('diagnose without both photos → 422; with both → 200 and audit carries photoIds', async () => {
    const { t, bookingId } = await arrivedBooking();
    const issue = await (async () => {
      const cat = await prisma.booking.findUnique({ where: { id: bookingId }, include: { service: true } });
      return seedIssue(cat!.service.categoryId);
    })();
    // 0 photos
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(422);
    // 1 of 2
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW');
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(422);
    // both
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP');
    const ok = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect(ok.statusCode).toBe(200);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'DIAGNOSED' } } });
    const meta = audit!.metadata as { photoIds?: string[] };
    expect(meta.photoIds).toHaveLength(2);
  });

  it('a soft-deleted (replaced-away) slot does not count', async () => {
    const { t, bookingId } = await arrivedBooking();
    const cat = await prisma.booking.findUnique({ where: { id: bookingId }, include: { service: true } });
    const issue = await seedIssue(cat!.service.categoryId);
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW');
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP');
    // simulate a slot whose only row got soft-deleted (no active replacement)
    await prisma.photoEvidence.updateMany({ where: { bookingId, kind: 'DIAGNOSIS_CLOSEUP' }, data: { deletedAt: new Date() } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(422);
  });
});

describe('photos in DTOs', () => {
  it('customer GET /me/bookings/:id and technician /mine carry {kind, capturedAt, url} for ACTIVE photos only', async () => {
    const { c, t, bookingId } = await arrivedBooking();
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW');
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP');
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP'); // retake — only the replacement shows

    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${bookingId}`, headers: auth(c.token) })).json();
    expect(got.photos).toHaveLength(2);
    const kinds = got.photos.map((p: { kind: string }) => p.kind).sort();
    expect(kinds).toEqual(['DIAGNOSIS_CLOSEUP', 'DIAGNOSIS_OVERVIEW']);
    for (const p of got.photos) {
      expect(p.url).toContain('read'); // signed READ url, never the raw key
      expect(p).not.toHaveProperty('r2Key');
    }
    const mine = (await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).json();
    const job = mine.find((j: { id: string }) => j.id === bookingId);
    expect(job.photos).toHaveLength(2);
  });
});
