import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { prisma as appPrisma } from '../../src/shared/database/prisma.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos } from './helpers.js';

// A fresh app per test: the global rate limiter (100 req/min, in-memory, per app instance) would
// otherwise be shared by every request in this file, which now exceeds it (429s in the late tests).
let app: FastifyInstance;
beforeEach(async () => { app = await buildApp(); await resetDb(); await flushTestRedis(); });
afterEach(() => app.close());
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a fresh booking all the way to ARRIVED; return ids + a seeded issue + a seeded catalog part. */
async function arrivedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id); // B4b: diagnose now requires both photo slots filled
  const issue = await seedIssue(f.cat.id);
  const part = await prisma.partsCatalog.create({ data: { sku: `P-${Math.random().toString(36).slice(2, 8)}`, name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
  return { c, t, f, bookingId: booking.id as string, issue, part };
}

describe('diagnose + parts cart', () => {
  it('technician diagnoses (ARRIVED→DIAGNOSED) with the issue snapshot', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect(res.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('DIAGNOSED');
    expect(row!.diagnosedIssueName).toBe('Compressor fault');
    expect(row!.diagnosedAt).not.toBeNull();
  });

  it('issue from a different category → 422', async () => {
    const { t, bookingId } = await arrivedBooking();
    const otherCat = await prisma.serviceCategory.create({ data: { name: `Fan-${Math.random().toString(36).slice(2, 8)}` } });
    const otherIssue = await prisma.diagnosedIssue.create({ data: { name: 'Blade', categoryId: otherCat.id } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: otherIssue.id } })).statusCode).toBe(422);
  });

  it('diagnose twice → 409; a non-assigned tech → 403; the customer → 403', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(409);
    const fresh = await arrivedBooking();
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${fresh.bookingId}/diagnose`, headers: auth(other.token), payload: { diagnosedIssueId: fresh.issue.id } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${fresh.bookingId}/diagnose`, headers: auth(fresh.c.token), payload: { diagnosedIssueId: fresh.issue.id } })).statusCode).toBe(403);
  });

  it('add a part snapshots the ceiling price; a catalog edit after add does NOT change the line', async () => {
    const { t, bookingId, part } = await arrivedBooking();
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    expect(add.statusCode).toBe(201);
    await prisma.partsCatalog.update({ where: { id: part.id }, data: { ceilingPricePaise: 999999 } });
    const lines = await prisma.bookingPart.findMany({ where: { bookingId } });
    expect(lines).toHaveLength(1);
    expect(lines[0]!.ceilingPricePaise).toBe(50000);
    expect(lines[0]!.qty).toBe(2);
  });

  it('qty < 1 → 400; unknown catalog part → 404; remove unknown line → 404', async () => {
    const { t, bookingId, part } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 0 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 100 } })).statusCode).toBe(400); // qty cap
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: '00000000-0000-0000-0000-000000000000', qty: 1 } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/00000000-0000-0000-0000-000000000000`, headers: auth(t.token) })).statusCode).toBe(404);
  });

  it('add/remove work while ARRIVED; remove works + writes audit', async () => {
    const { t, bookingId, part } = await arrivedBooking();
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) })).statusCode).toBe(204);
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(0);
    const audits = await prisma.auditLog.findMany({ where: { action: 'DIAGNOSIS_UPDATED' } });
    expect(audits.length).toBeGreaterThanOrEqual(2); // part_added + part_removed
  });

  it('after diagnose the cart is locked: add and remove → 409 with the locked message', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(add.statusCode).toBe(409);
    expect(add.json().message).toBe('The cart is locked — the diagnosis has been submitted');
    const del = await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) });
    expect(del.statusCode).toBe(409);
    expect(del.json().message).toBe('The cart is locked — the diagnosis has been submitted');
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(1);
  });

  it('before arrival the cart is not open: add while EN_ROUTE → 409 "Job is not in ARRIVED"', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
    const part = await prisma.partsCatalog.create({ data: { sku: `P-${Math.random().toString(36).slice(2, 8)}`, name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(res.statusCode).toBe(409);
    expect(res.json().message).toBe('Job is not in ARRIVED');
  });

  it('diagnose records the cart it sent (partCount + partsTotalPaise) in the transition evidence', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking(); // part = 50000 paise
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const rows = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' } });
    const toDiagnosed = rows.map((r) => r.metadata as Record<string, unknown>).find((m) => m.bookingId === bookingId && m.to === 'DIAGNOSED');
    expect(toDiagnosed).toMatchObject({ partCount: 1, partsTotalPaise: 100000 });
  });

  it('an empty cart is a valid labor-only estimate (partCount 0, partsTotalPaise 0)', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const rows = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' } });
    const toDiagnosed = rows.map((r) => r.metadata as Record<string, unknown>).find((m) => m.bookingId === bookingId && m.to === 'DIAGNOSED');
    expect(toDiagnosed).toMatchObject({ partCount: 0, partsTotalPaise: 0 });
  });

  it('a part from a different category → 422; a generic (null-category) part is allowed', async () => {
    const { t, bookingId } = await arrivedBooking();
    const otherCat = await prisma.serviceCategory.create({ data: { name: `Other-${Math.random().toString(36).slice(2, 8)}` } });
    const wrongPart = await prisma.partsCatalog.create({ data: { sku: `W-${Math.random().toString(36).slice(2, 8)}`, name: 'Wrong', ceilingPricePaise: 1000, categoryId: otherCat.id } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: wrongPart.id, qty: 1 } })).statusCode).toBe(422);
    const generic = await prisma.partsCatalog.create({ data: { sku: `G-${Math.random().toString(36).slice(2, 8)}`, name: 'Generic screw', ceilingPricePaise: 500, categoryId: null } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: generic.id, qty: 1 } })).statusCode).toBe(201);
  });
});

describe('estimate integrity: one line per part, line cap, per-line evidence, ownership, races', () => {
  /** The DIAGNOSED transition's audit metadata for this booking. */
  async function toDiagnosedEvidence(bookingId: string) {
    const rows = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' } });
    return rows.map((r) => r.metadata as Record<string, unknown>).find((m) => m.bookingId === bookingId && m.to === 'DIAGNOSED');
  }
  async function partAudits(bookingId: string, action: 'part_added' | 'part_removed') {
    const rows = await prisma.auditLog.findMany({ where: { action: 'DIAGNOSIS_UPDATED' }, orderBy: { createdAt: 'asc' } });
    return rows.map((r) => r.metadata as Record<string, unknown>).filter((m) => m.bookingId === bookingId && m.action === action);
  }

  it('adding the same part twice → 409 (one line per part) and the cart keeps a single line', async () => {
    const { t, bookingId, part } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).statusCode).toBe(201);
    const again = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 3 } });
    expect(again.statusCode).toBe(409);
    expect(again.json().message).toBe('This part is already in the estimate — remove it to change the quantity');
    const lines = await prisma.bookingPart.findMany({ where: { bookingId } });
    expect(lines).toHaveLength(1);
    expect(lines[0]!.qty).toBe(1);
  });

  it('an estimate lists at most 20 parts: the 21st distinct part → 422', async () => {
    const { t, f, bookingId } = await arrivedBooking();
    const parts = [];
    for (let i = 0; i < 21; i++) {
      parts.push(await prisma.partsCatalog.create({ data: { sku: `CAP-${i}-${Math.random().toString(36).slice(2, 8)}`, name: `Part ${i}`, ceilingPricePaise: 1000, categoryId: f.cat.id } }));
    }
    for (const p of parts.slice(0, 20)) {
      expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: p.id, qty: 1 } })).statusCode).toBe(201);
    }
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: parts[20]!.id, qty: 1 } });
    expect(res.statusCode).toBe(422);
    expect(res.json().message).toBe('An estimate can list at most 20 parts');
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(20);
  });

  it('diagnose evidence carries every line (sku, name, qty, ceilingPricePaise) of the frozen cart', async () => {
    const { t, f, bookingId, issue, part } = await arrivedBooking(); // part = Capacitor @ 50000
    const fan = await prisma.partsCatalog.create({ data: { sku: `FAN-${Math.random().toString(36).slice(2, 8)}`, name: 'Fan motor', ceilingPricePaise: 120000, categoryId: f.cat.id } });
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: fan.id, qty: 1 } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const cart = await prisma.bookingPart.findMany({ where: { bookingId }, orderBy: { createdAt: 'asc' } });
    const evidence = await toDiagnosedEvidence(bookingId);
    expect(evidence).toMatchObject({ partCount: 2, partsTotalPaise: 220000 });
    expect(evidence!.lines).toEqual(cart.map((l) => ({ sku: l.sku, name: l.name, qty: l.qty, ceilingPricePaise: l.ceilingPricePaise })));
  });

  it('add/remove audits carry lineId, qty and ceilingPricePaise; a second remove of the same line writes no second part_removed', async () => {
    const { t, bookingId, part } = await arrivedBooking();
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } })).json();
    const [added] = await partAudits(bookingId, 'part_added');
    expect(added).toMatchObject({ lineId: line.id, sku: part.sku, qty: 2, ceilingPricePaise: 50000 });
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) })).statusCode).toBe(204);
    const removed = await partAudits(bookingId, 'part_removed');
    expect(removed).toHaveLength(1);
    expect(removed[0]).toMatchObject({ lineId: line.id, sku: part.sku, qty: 2, ceilingPricePaise: 50000 });
    // A concurrent double-remove: the second request read the line before the first deleted it, so it
    // reaches the transaction and its deleteMany deletes 0 rows. Simulate that interleaving
    // deterministically by handing the service's pre-check the stale line once.
    const stale = { id: line.id, bookingId, partsCatalogId: part.id, sku: part.sku, name: part.name, ceilingPricePaise: 50000, qty: 2, createdAt: new Date() };
    const spy = vi.spyOn(appPrisma.bookingPart, 'findFirst').mockResolvedValueOnce(stale as never);
    try {
      expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) })).statusCode).toBe(204);
    } finally {
      spy.mockRestore();
    }
    expect(await partAudits(bookingId, 'part_removed')).toHaveLength(1);
  });

  it('another VERIFIED technician cannot add to or remove from the cart (403); a customer cannot add (403); cart unchanged', async () => {
    const { c, t, bookingId, part } = await arrivedBooking();
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    const other = await makeTechnician(['AC']);
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(other.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(add.statusCode).toBe(403);
    expect(add.json().message).toBe('This job is not assigned to you');
    expect(add.json().code).toBe('JOB_NOT_ASSIGNED');
    const del = await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(other.token) });
    expect(del.statusCode).toBe(403);
    expect(del.json().message).toBe('This job is not assigned to you');
    expect(del.json().code).toBe('JOB_NOT_ASSIGNED');
    const asCustomer = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(c.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(asCustomer.statusCode).toBe(403);
    const lines = await prisma.bookingPart.findMany({ where: { bookingId } });
    expect(lines.map((l) => ({ id: l.id, qty: l.qty }))).toEqual([{ id: line.id, qty: 1 }]);
  });

  it('a missing booking → 404 "Job not found" for add and remove', async () => {
    const { t, part } = await arrivedBooking();
    const missing = '00000000-0000-0000-0000-000000000000';
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${missing}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(add.statusCode).toBe(404);
    expect(add.json().message).toBe('Job not found');
    expect(add.json().code).toBe('JOB_NOT_FOUND');
    const del = await app.inject({ method: 'DELETE', url: `/technician/jobs/${missing}/parts/${missing}`, headers: auth(t.token) });
    expect(del.statusCode).toBe(404);
    expect(del.json().message).toBe('Job not found');
    expect(del.json().code).toBe('JOB_NOT_FOUND');
  });

  it('an add racing the diagnose is consistent: 201 ⇒ partCount 1, 409 locked ⇒ partCount 0 (never 201 with 0)', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    const [add, diagnose] = await Promise.all([
      app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } }),
      app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } }),
    ]);
    expect(diagnose.statusCode).toBe(200);
    const evidence = await toDiagnosedEvidence(bookingId);
    if (add.statusCode === 201) {
      expect(evidence).toMatchObject({ partCount: 1 });
    } else {
      expect(add.statusCode).toBe(409);
      expect(add.json().message).toBe('The cart is locked — the diagnosis has been submitted');
      expect(evidence).toMatchObject({ partCount: 0 });
    }
    expect(evidence!.partCount).toBe(await prisma.bookingPart.count({ where: { bookingId } }));
  });
});

describe('diagnose binds to the confirmed cart (expectedPartLineIds)', () => {
  const ESTIMATE_CHANGED_MESSAGE = 'The estimate changed — check the parts and send again';
  async function addLine(t: { token: string }, bookingId: string, partsCatalogId: string, qty = 1): Promise<string> {
    return (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId, qty } })).json().id;
  }
  async function stateOf(bookingId: string) {
    return (await prisma.booking.findUniqueOrThrow({ where: { id: bookingId } })).state;
  }

  it('the confirmed snapshot matches the cart (any order) → 200 DIAGNOSED', async () => {
    const { t, f, bookingId, issue, part } = await arrivedBooking();
    const fan = await prisma.partsCatalog.create({ data: { sku: `FAN-${Math.random().toString(36).slice(2, 8)}`, name: 'Fan motor', ceilingPricePaise: 120000, categoryId: f.cat.id } });
    const a = await addLine(t, bookingId, part.id, 2);
    const b = await addLine(t, bookingId, fan.id);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id, expectedPartLineIds: [b, a] } });
    expect(res.statusCode).toBe(200);
    expect(await stateOf(bookingId)).toBe('DIAGNOSED');
  });

  it('an empty confirmed snapshot matches an empty cart → 200', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id, expectedPartLineIds: [] } });
    expect(res.statusCode).toBe(200);
  });

  it('a line the snapshot did not include → 409 ESTIMATE_CHANGED; booking stays ARRIVED and nothing is written', async () => {
    const { t, f, bookingId, issue, part } = await arrivedBooking();
    const confirmed = await addLine(t, bookingId, part.id);
    // A second line lands after the technician opened the confirm dialog (another device, a stale tab).
    const fan = await prisma.partsCatalog.create({ data: { sku: `FAN-${Math.random().toString(36).slice(2, 8)}`, name: 'Fan motor', ceilingPricePaise: 120000, categoryId: f.cat.id } });
    await addLine(t, bookingId, fan.id);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id, expectedPartLineIds: [confirmed] } });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'ESTIMATE_CHANGED', message: ESTIMATE_CHANGED_MESSAGE });
    const row = await prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
    expect(row.state).toBe('ARRIVED');
    expect(row.diagnosedAt).toBeNull();
    expect(row.diagnosedIssueId).toBeNull();
    const audits = await prisma.auditLog.findMany({ where: { action: { in: ['DIAGNOSIS_UPDATED', 'BOOKING_STATE_CHANGED'] } } });
    const metas = audits.map((r) => r.metadata as Record<string, unknown>).filter((m) => m.bookingId === bookingId);
    expect(metas.filter((m) => m.action === 'diagnosed' || m.to === 'DIAGNOSED')).toHaveLength(0);
    // The cart is still open — the technician can review and send again.
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(2);
  });

  it('a snapshot listing a line that was removed → 409 ESTIMATE_CHANGED; booking stays ARRIVED', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    const line = await addLine(t, bookingId, part.id);
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line}`, headers: auth(t.token) })).statusCode).toBe(204);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id, expectedPartLineIds: [line] } });
    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('ESTIMATE_CHANGED');
    expect(res.json().message).toBe(ESTIMATE_CHANGED_MESSAGE);
    expect(await stateOf(bookingId)).toBe('ARRIVED');
  });

  it('field absent → 200 (older app builds keep working)', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    await addLine(t, bookingId, part.id);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect(res.statusCode).toBe(200);
    expect(await stateOf(bookingId)).toBe('DIAGNOSED');
  });

  it('an unknown extra body field → 400; more than 20 ids → 400', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    const extra = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id, expectedPartLineIds: [], totalPaise: 1 } });
    expect(extra.statusCode).toBe(400);
    const tooMany = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id, expectedPartLineIds: Array.from({ length: 21 }, (_, i) => `l${i}`) } });
    expect(tooMany.statusCode).toBe(400);
    expect(await stateOf(bookingId)).toBe('ARRIVED');
  });
});

describe('approve / decline', () => {
  async function diagnosedWithPart() {
    const a = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/parts`, headers: auth(a.t.token), payload: { partsCatalogId: a.part.id, qty: 1 } });
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/diagnose`, headers: auth(a.t.token), payload: { diagnosedIssueId: a.issue.id } });
    return a;
  }

  it('customer GET + list both show diagnosis + parts + the same parts-inclusive estimate', async () => {
    const a = await diagnosedWithPart();
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${a.bookingId}`, headers: auth(a.c.token) })).json();
    expect(got.diagnosis.issueName).toBe('Compressor fault');
    expect(got.parts).toHaveLength(1);
    expect(got.estimate.partsPaise).toBe(50000);
    // labor 60000 + parts 50000 − visitFee 14900 = 95100
    expect(got.estimate.totalPayablePaise).toBe(95100);
    // the list view must agree with the detail view (not a labor-only 45100)
    const list = (await app.inject({ method: 'GET', url: '/me/bookings', headers: auth(a.c.token) })).json();
    const row = list.find((b: { id: string }) => b.id === a.bookingId);
    expect(row.parts).toHaveLength(1);
    expect(row.estimate.totalPayablePaise).toBe(95100);
  });

  it('approve → CUSTOMER_APPROVED; cart frozen (part add after approve → 409)', async () => {
    const a = await diagnosedWithPart();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(a.c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('CUSTOMER_APPROVED');
    expect(res.json().estimate.totalPayablePaise).toBe(95100); // credit still applies post-approval
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/parts`, headers: auth(a.t.token), payload: { partsCatalogId: a.part.id, qty: 1 } })).statusCode).toBe(409);
  });


  it('decline → DECLINED_BY_CUSTOMER (terminal) + declinedAt; visitFeeLockedAt stays set', async () => {
    const a = await diagnosedWithPart();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/decline`, headers: auth(a.c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('DECLINED_BY_CUSTOMER');
    expect(res.json().estimate.totalPayablePaise).toBe(0); // repair won't happen → nothing payable for it
    const row = await prisma.booking.findUnique({ where: { id: a.bookingId } });
    expect(row!.declinedAt).not.toBeNull();
    expect(row!.visitFeeLockedAt).not.toBeNull(); // set at ARRIVED (B3), unchanged
  });

  it('decline evidence records the cart that was declined (partCount + partsTotalPaise), like approve', async () => {
    const a = await diagnosedWithPart(); // 1 × 50000
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/decline`, headers: auth(a.c.token) })).statusCode).toBe(200);
    const rows = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' } });
    const toDeclined = rows.map((r) => r.metadata as Record<string, unknown>).find((m) => m.bookingId === a.bookingId && m.to === 'DECLINED_BY_CUSTOMER');
    expect(toDeclined).toMatchObject({ source: 'customer_decline', partCount: 1, partsTotalPaise: 50000 });
  });

  it('approve/decline from non-DIAGNOSED → 409; another customer → 404; the technician → 403', async () => {
    const a = await diagnosedWithPart();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(a.t.token) })).statusCode).toBe(403);
    await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(a.c.token) });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/decline`, headers: auth(a.c.token) })).statusCode).toBe(409); // already approved
  });
});
