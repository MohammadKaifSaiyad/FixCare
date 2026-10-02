import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedDiagnosisPhotos } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** A booking driven to ARRIVED for a fresh AC technician, with both diagnosis photos seeded. */
async function arrivedJob(opts?: { visitFeePaise?: number; laborPaise?: number }) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId, opts);
  const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id);
  return { c, f, t, bookingId: booking.id as string };
}

describe('GET /technician/jobs/:id', () => {
  it('assigned technician gets the job with parts[], service.categoryId and active photos (masked phone, no name)', async () => {
    const { f, t, bookingId } = await arrivedJob();
    const part = await prisma.partsCatalog.create({ data: { sku: 'CAP-1', name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } })).json();
    const res = await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.id).toBe(bookingId);
    expect(body.state).toBe('ARRIVED');
    expect(body.service.categoryId).toBe(f.cat.id);
    expect(body.parts).toEqual([{ id: line.id, partsCatalogId: part.id, sku: 'CAP-1', name: 'Capacitor', qty: 2, ceilingPricePaise: 50000 }]);
    expect(body.photos.map((p: { kind: string }) => p.kind).sort()).toEqual(['DIAGNOSIS_CLOSEUP', 'DIAGNOSIS_OVERVIEW']);
    expect(Object.keys(body.customer)).toEqual(['maskedPhone']);
  });

  it('another technician → 403; a customer → 403; an unverified technician → 403; a missing job → 404', async () => {
    const { c, bookingId } = await arrivedJob();
    const other = await makeTechnician(['AC']);
    const foreign = await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(other.token) });
    expect(foreign.statusCode).toBe(403);
    expect(foreign.json().message).toBe('This job is not assigned to you');
    // Stable machine code — the app's "no longer assigned" vanish keys on this, never on the message.
    expect(foreign.json().code).toBe('JOB_NOT_ASSIGNED');
    const asCustomer = await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(c.token) });
    expect(asCustomer.statusCode).toBe(403);
    expect(asCustomer.json().message).toBe('Technician access required');
    const pending = await makeTechnician(['AC'], 'PENDING');
    const unverified = await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(pending.token) });
    expect(unverified.statusCode).toBe(403);
    // The app shows this one verbatim (a suspended/unverified technician is not "no longer assigned").
    expect(unverified.json().message).toBe('Verified technician required');
    expect(unverified.json().code).toBe('TECHNICIAN_NOT_VERIFIED'); // NOT a job code — the app must not treat it as a vanish
    const t2 = await makeTechnician(['AC']);
    const missing = await app.inject({ method: 'GET', url: '/technician/jobs/00000000-0000-0000-0000-000000000000', headers: auth(t2.token) });
    expect(missing.statusCode).toBe(404);
    expect(missing.json().message).toBe('Job not found');
    expect(missing.json().code).toBe('JOB_NOT_FOUND');
  });

  it('carries the server-computed customer quote: an ARRIVED 2 × ₹500 cart shows labor + parts − visit-fee credit', async () => {
    const { f, t, bookingId } = await arrivedJob();
    const part = await prisma.partsCatalog.create({ data: { sku: 'CAP-Q', name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    const body = (await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(t.token) })).json();
    expect(body.state).toBe('ARRIVED');
    // The quote the customer will approve at DIAGNOSED — the visit-fee credit applied even though the
    // job is still ARRIVED (the technician previews exactly what the customer will see).
    expect(body.customerQuote).toEqual({
      laborPaise: f.laborPaise,
      partsPaise: 100000,
      visitFeeCreditPaise: f.visitFeePaise,
      totalPayablePaise: f.laborPaise + 100000 - f.visitFeePaise,
    });
  });

  it('customer quote floors at 0 when the labor is below the visit fee (empty cart)', async () => {
    const { t, bookingId } = await arrivedJob({ visitFeePaise: 14900, laborPaise: 10000 });
    const body = (await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(t.token) })).json();
    expect(body.customerQuote).toEqual({ laborPaise: 10000, partsPaise: 0, visitFeeCreditPaise: 14900, totalPayablePaise: 0 });
  });

  it('static routes still win: /technician/jobs/available and /mine are not treated as an :id', async () => {
    const { t } = await arrivedJob();
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t.token) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).statusCode).toBe(200);
  });

  it('available and mine carry service.categoryId', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    const available = (await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t.token) })).json();
    expect(available.find((j: { id: string }) => j.id === booking.id).service.categoryId).toBe(f.cat.id);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    const mine = (await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).json();
    expect(mine.find((j: { id: string }) => j.id === booking.id).service.categoryId).toBe(f.cat.id);
  });
});
