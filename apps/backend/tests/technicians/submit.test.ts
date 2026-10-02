import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
const submit = (token: string) => app.inject({ method: 'POST', url: '/technician/me/submit', headers: auth(token) });
async function zone(name = 'Padra') { return prisma.zone.create({ data: { name, visitFeePaise: 9900 } }); }
const audits = () => prisma.auditLog.findMany({ where: { action: 'TECHNICIAN_STATUS_CHANGED' } });

describe('POST /technician/me/submit', () => {
  it('a complete PENDING profile → KYC_SUBMITTED, submittedAt set, one audit row by the technician', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    const res = await submit(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: t.technicianId, status: 'KYC_SUBMITTED', zones: [{ id: z.id, name: 'Padra' }] });
    expect(res.json().submittedAt).toEqual(expect.any(String));
    const a = await audits();
    expect(a).toHaveLength(1);
    expect(a[0]).toMatchObject({ actorType: 'USER', actorId: t.userId, subjectId: t.technicianId, metadata: { from: 'PENDING', to: 'KYC_SUBMITTED' } });
  });

  it('incomplete → 422 with a clear message, status unchanged', async () => {
    const z = await zone();
    const inactive = await prisma.zone.create({ data: { name: 'Old', visitFeePaise: 9900, status: 'INACTIVE' } });
    const cases: Array<[Promise<{ token: string; technicianId: string }>, string]> = [
      [makeTechnician([], 'PENDING', [z.id]), 'Choose at least one skill before submitting'],
      [makeTechnician(['AC'], 'PENDING', []), 'Choose at least one service zone before submitting'],
      [makeTechnician(['AC'], 'PENDING', [inactive.id]), 'One of your service zones is no longer available — update your zones and submit again'],
    ];
    for (const [made, message] of cases) {
      const t = await made;
      const res = await submit(t.token);
      expect(res.statusCode).toBe(422);
      expect(res.json().message).toBe(message);
      expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('PENDING');
    }
    const noName = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await prisma.technician.update({ where: { id: noName.technicianId }, data: { name: '' } });
    expect((await submit(noName.token)).json().message).toBe('Add your name before submitting');
    expect(await audits()).toHaveLength(0);
  });

  it('already submitted / verified / suspended → 409 INVALID_TECHNICIAN_TRANSITION', async () => {
    const z = await zone();
    for (const status of ['KYC_SUBMITTED', 'VERIFIED', 'SUSPENDED'] as const) {
      const t = await makeTechnician(['AC'], status, [z.id]);
      const res = await submit(t.token);
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ code: 'INVALID_TECHNICIAN_TRANSITION', message: 'Your profile has already been submitted' });
    }
  });

  it('two submits racing → exactly one succeeds and exactly one audit row', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    const [a, b] = await Promise.all([submit(t.token), submit(t.token)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await audits()).toHaveLength(1);
  });

  it('a resubmit after send-back keeps reviewNote until the next decision', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { reviewNote: 'Remove Wiring' } });
    const res = await submit(t.token);
    expect(res.json()).toMatchObject({ status: 'KYC_SUBMITTED', reviewNote: 'Remove Wiring' });
  });

  it('after submit the profile is locked; non-technicians → 403; no token → 401', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await submit(t.token);
    expect((await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(t.token), payload: { name: 'X' } })).statusCode).toBe(409);
    const c = await makeCustomer();
    expect((await submit(c.token)).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/technician/me/submit' })).statusCode).toBe(401);
  });
});
