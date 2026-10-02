import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
async function zone(name: string, extra: { status?: 'ACTIVE' | 'INACTIVE'; deletedAt?: Date } = {}) {
  return prisma.zone.create({ data: { name, visitFeePaise: 9900, ...extra } });
}
const patch = (token: string, payload: object) => app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload });

describe('technician profile — zones + lock', () => {
  it('PENDING: sets name, skills and zones (replacing earlier zones); audit lists field names only', async () => {
    const t = await makeTechnician([], 'PENDING');
    const padra = await zone('Padra');
    const vadodara = await zone('Vadodara');
    expect((await patch(t.token, { zoneIds: [padra.id] })).statusCode).toBe(200);
    const res = await patch(t.token, { name: '  Ramesh  ', skills: ['AC', 'FAN'], zoneIds: [vadodara.id] });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      id: t.technicianId, role: 'TECHNICIAN', name: 'Ramesh', skills: ['AC', 'FAN'], status: 'PENDING',
      zones: [{ id: vadodara.id, name: 'Vadodara' }], reviewNote: null, submittedAt: null,
    });
    expect(await prisma.technicianZone.count({ where: { technicianId: t.technicianId } })).toBe(1);
    const audits = await prisma.auditLog.findMany({ where: { action: 'PROFILE_UPDATED', actorId: t.userId }, orderBy: { createdAt: 'asc' } });
    expect(audits).toHaveLength(2);
    expect(audits[1]!.metadata).toEqual({ fields: ['name', 'skills', 'zoneIds'] });
    expect(JSON.stringify(audits)).not.toContain('Ramesh');
  });

  it('locked once submitted: 409 PROFILE_LOCKED in KYC_SUBMITTED, VERIFIED and SUSPENDED; nothing changes', async () => {
    const z = await zone('Padra');
    for (const status of ['KYC_SUBMITTED', 'VERIFIED', 'SUSPENDED'] as const) {
      const t = await makeTechnician(['AC'], status, [z.id]);
      const res = await patch(t.token, { skills: ['AC', 'WIRING'] });
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ code: 'PROFILE_LOCKED', message: 'Your profile is locked while under review' });
      expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).skills).toEqual(['AC']);
    }
    expect(await prisma.auditLog.count({ where: { action: 'PROFILE_UPDATED' } })).toBe(0);
  });

  it('an inactive, deleted or unknown zone → 422 and nothing changes', async () => {
    const t = await makeTechnician(['AC'], 'PENDING');
    const inactive = await zone('Old', { status: 'INACTIVE' });
    const deleted = await zone('Gone', { deletedAt: new Date() });
    for (const id of [inactive.id, deleted.id, '00000000-0000-0000-0000-000000000000']) {
      const res = await patch(t.token, { zoneIds: [id] });
      expect(res.statusCode).toBe(422);
      expect(res.json().message).toBe('Choose service zones from the list');
    }
    expect(await prisma.technicianZone.count()).toBe(0);
  });

  it('400 for repeated skills or zones, an empty zone list, a blank or over-long name, unknown keys', async () => {
    const t = await makeTechnician(['AC'], 'PENDING');
    const z = await zone('Padra');
    for (const payload of [
      { skills: ['AC', 'AC'] }, { zoneIds: [z.id, z.id] }, { zoneIds: [] }, { zoneIds: ['nope'] },
      { name: '   ' }, { name: 'x'.repeat(81) }, { status: 'VERIFIED' }, {},
    ]) {
      expect((await patch(t.token, payload)).statusCode).toBe(400);
    }
  });

  it('GET /me/profile carries zones, reviewNote and submittedAt; customer profile unchanged', async () => {
    const z = await zone('Padra');
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { reviewNote: 'Add your full name', submittedAt: new Date('2026-10-01T10:00:00.000Z') } });
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ zones: [{ id: z.id, name: 'Padra' }], reviewNote: 'Add your full name', submittedAt: '2026-10-01T10:00:00.000Z' });
    const c = await makeCustomer();
    const cust = await app.inject({ method: 'GET', url: '/me/profile', headers: auth(c.token) });
    expect(Object.keys(cust.json()).sort()).toEqual(['id', 'name', 'role', 'status']);
  });
});
