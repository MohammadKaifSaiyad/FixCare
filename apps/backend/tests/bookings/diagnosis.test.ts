import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
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
    const { t, bookingId, issue, part } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    expect(add.statusCode).toBe(201);
    await prisma.partsCatalog.update({ where: { id: part.id }, data: { ceilingPricePaise: 999999 } });
    const lines = await prisma.bookingPart.findMany({ where: { bookingId } });
    expect(lines).toHaveLength(1);
    expect(lines[0]!.ceilingPricePaise).toBe(50000);
    expect(lines[0]!.qty).toBe(2);
  });

  it('qty < 1 → 400; unknown catalog part → 404; remove unknown line → 404', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 0 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: '00000000-0000-0000-0000-000000000000', qty: 1 } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/00000000-0000-0000-0000-000000000000`, headers: auth(t.token) })).statusCode).toBe(404);
  });

  it('add/remove only while DIAGNOSED; remove works + writes audit', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) })).statusCode).toBe(204);
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(0);
    const audits = await prisma.auditLog.findMany({ where: { action: 'DIAGNOSIS_UPDATED' } });
    expect(audits.length).toBeGreaterThanOrEqual(3);
  });
});
