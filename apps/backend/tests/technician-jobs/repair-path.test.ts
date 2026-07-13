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

/** Booking driven to CUSTOMER_APPROVED (with a seeded cart part so the parts path is legal). */
async function approvedBooking(withPart = true) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id); // diagnose requires both slots (B4b)
  const issue = await seedIssue(f.cat.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
  if (withPart) {
    // Seed the cart line directly (snapshot fields) — the parts ENDPOINT has its own tests in
    // diagnosis.test.ts. partsCatalogId is a required FK, so create the catalog row first.
    const cat = await prisma.partsCatalog.create({ data: { sku: `SEED-${Math.random().toString(36).slice(2, 8)}`, name: 'Seed part', ceilingPricePaise: 10000 } });
    await prisma.bookingPart.create({ data: { bookingId: booking.id, partsCatalogId: cat.id, sku: cat.sku, name: cat.name, ceilingPricePaise: cat.ceilingPricePaise, qty: 1 } });
  }
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/approve`, headers: auth(c.token) });
  return { c, t, bookingId: booking.id as string };
}

describe('repair path', () => {
  it('parts detour: CUSTOMER_APPROVED → PARTS_REQUESTED → PARTS_ACQUIRED → REPAIR_IN_PROGRESS', async () => {
    const { t, bookingId } = await approvedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-needed`, headers: auth(t.token) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-acquired`, headers: auth(t.token) })).statusCode).toBe(200);
    const start = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) });
    expect(start.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('REPAIR_IN_PROGRESS');
    expect(row!.repairStartedAt).not.toBeNull();
  });

  it('direct path: CUSTOMER_APPROVED → REPAIR_IN_PROGRESS (no parts detour)', async () => {
    const { t, bookingId } = await approvedBooking(false);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) })).statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('REPAIR_IN_PROGRESS');
    expect(row!.repairStartedAt).not.toBeNull(); // set on the direct path too, not just the parts detour
  });

  it('parts-needed with an EMPTY cart → 422 (dishonest detour)', async () => {
    const { t, bookingId } = await approvedBooking(false);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-needed`, headers: auth(t.token) })).statusCode).toBe(422);
  });

  it('actor + state guards: foreign tech 403, customer 403, wrong-state 409, audit written', async () => {
    const { c, t, bookingId } = await approvedBooking();
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(other.token) })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(c.token) })).statusCode).toBe(403);
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) });
    // already in repair — every earlier transition now 409s
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-needed`, headers: auth(t.token) })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) })).statusCode).toBe(409);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'REPAIR_IN_PROGRESS' } } });
    expect(audit).not.toBeNull();
  });
});

describe('repair photos + complete-repair', () => {
  async function inRepairBooking() {
    const a = await approvedBooking(false);
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/start-repair`, headers: auth(a.t.token) });
    return a;
  }

  it('repair photo sign works in REPAIR_IN_PROGRESS; diagnosis kinds are 409 there (window map)', async () => {
    const { t, bookingId } = await inRepairBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'REPAIR_OLD_PART', contentLengthBytes: 1000 } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(409);
  });

  it('complete-repair: 422 until all 3 repair slots active; then 200 with photoIds in audit + repairCompletedAt', async () => {
    const { t, bookingId } = await inRepairBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) })).statusCode).toBe(422);
    await seedRepairPhotos(bookingId);
    // a soft-deleted slot must not count: kill one and re-check
    await prisma.photoEvidence.updateMany({ where: { bookingId, kind: 'REPAIR_INSTALLED' }, data: { deletedAt: new Date() } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) })).statusCode).toBe(422);
    await prisma.photoEvidence.updateMany({ where: { bookingId, kind: 'REPAIR_INSTALLED' }, data: { deletedAt: null } });
    const ok = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) });
    expect(ok.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('REPAIR_COMPLETE');
    expect(row!.repairCompletedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'REPAIR_COMPLETE' } } });
    expect(((audit!.metadata as { photoIds: string[] }).photoIds)).toHaveLength(3);
  });

  it('diagnosis photos do NOT satisfy the repair gate', async () => {
    const { t, bookingId } = await inRepairBooking();
    // approvedBooking already seeded both diagnosis slots — still 422:
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) })).statusCode).toBe(422);
  });
});
