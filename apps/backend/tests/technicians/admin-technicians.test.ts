import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdmin, makeAdminToken, makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
const post = (token: string, url: string, payload?: object) =>
  app.inject({ method: 'POST', url, headers: auth(token), ...(payload === undefined ? {} : { payload }) });
async function zone(name = 'Padra') { return prisma.zone.create({ data: { name, visitFeePaise: 9900 } }); }
const statusOf = async (id: string) => (await prisma.technician.findUniqueOrThrow({ where: { id } })).status;
const audits = (subjectId: string) =>
  prisma.auditLog.findMany({ where: { action: 'TECHNICIAN_STATUS_CHANGED', subjectId }, orderBy: { createdAt: 'asc' } });
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('admin technicians', () => {
  it('walls every route: 401 without a token; 403 for a SUPPORT admin, a customer, a technician', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const callers = [await makeAdminToken('SUPPORT'), (await makeCustomer()).token, t.token];
    const routes = [
      { method: 'GET' as const, url: '/admin/technicians' },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/verify` },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/send-back`, payload: { reason: 'x' } },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/suspend`, payload: { reason: 'x' } },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/reinstate` },
      { method: 'PATCH' as const, url: `/admin/technicians/${t.technicianId}`, payload: { skills: ['FAN'] } },
    ];
    for (const r of routes) {
      expect((await app.inject(r)).statusCode).toBe(401);
      for (const token of callers) expect((await app.inject({ ...r, headers: auth(token) })).statusCode).toBe(403);
    }
    expect(await statusOf(t.technicianId)).toBe('KYC_SUBMITTED');
  });

  it('lists by status, oldest submission first, phone masked and never in full', async () => {
    const admin = await makeAdminToken();
    const z = await zone();
    const a = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const b = await makeTechnician(['FAN'], 'KYC_SUBMITTED', [z.id]);
    await makeTechnician(['AC'], 'VERIFIED', [z.id]);
    await prisma.technician.update({ where: { id: a.technicianId }, data: { submittedAt: new Date('2026-10-01T10:00:00Z') } });
    await prisma.technician.update({ where: { id: b.technicianId }, data: { submittedAt: new Date('2026-10-01T09:00:00Z') } });
    const res = await app.inject({ method: 'GET', url: '/admin/technicians?status=KYC_SUBMITTED', headers: auth(admin) });
    expect(res.statusCode).toBe(200);
    const list = res.json() as Array<Record<string, unknown>>;
    expect(list.map((x) => x.id)).toEqual([b.technicianId, a.technicianId]);
    const phone = (await prisma.user.findUniqueOrThrow({ where: { id: a.userId } })).phone;
    expect(list[1]).toMatchObject({
      maskedPhone: `••••••${phone.slice(-4)}`, name: 'Tech', skills: ['AC'], status: 'KYC_SUBMITTED',
      zones: [{ id: z.id, name: 'Padra' }], submittedAt: '2026-10-01T10:00:00.000Z', reviewedAt: null, reviewNote: null,
    });
    expect(res.body).not.toContain(phone);
    expect((await app.inject({ method: 'GET', url: '/admin/technicians', headers: auth(admin) })).json()).toHaveLength(3);
    expect((await app.inject({ method: 'GET', url: '/admin/technicians?status=NOPE', headers: auth(admin) })).statusCode).toBe(400);
  });

  it('verify: KYC_SUBMITTED → VERIFIED, reviewedAt set, note cleared, one audit row by the admin', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { reviewNote: 'old note' } });
    const admin = await makeAdmin();
    const res = await post(admin.token, `/admin/technicians/${t.technicianId}/verify`);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: t.technicianId, status: 'VERIFIED', reviewNote: null, reviewedAt: expect.any(String) });
    const a = await audits(t.technicianId);
    expect(a).toHaveLength(1);
    expect(a[0]).toMatchObject({ actorType: 'ADMIN', actorId: admin.userId, metadata: { from: 'KYC_SUBMITTED', to: 'VERIFIED' } });
  });

  it('send-back: reason required (1..500); KYC_SUBMITTED → PENDING with the note; the technician can edit again', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const admin = await makeAdminToken();
    const url = `/admin/technicians/${t.technicianId}/send-back`;
    for (const payload of [undefined, {}, { reason: '   ' }, { reason: 'x'.repeat(501) }, { reason: 'ok', extra: 1 }, { reason: 'Call me on 9876543210' }]) {
      expect((await post(admin, url, payload)).statusCode).toBe(400);
    }
    const reason = 'Add the Wiring skill only if you hold a licence (visit 2 of 3)';
    const res = await post(admin, url, { reason });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'PENDING', reviewNote: reason });
    expect((await audits(t.technicianId))[0]!.metadata).toEqual({ from: 'KYC_SUBMITTED', to: 'PENDING', reason });
    expect((await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(t.token), payload: { skills: ['AC'] } })).statusCode).toBe(200);
  });

  it('suspend (reason) and reinstate; every disallowed move → 409 INVALID_TECHNICIAN_TRANSITION', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'VERIFIED', [z.id]);
    const admin = await makeAdminToken();
    const base = `/admin/technicians/${t.technicianId}`;
    expect((await post(admin, `${base}/suspend`, {})).statusCode).toBe(400);
    expect((await post(admin, `${base}/suspend`, { reason: 'Customer complaint under review' })).json()).toMatchObject({ status: 'SUSPENDED', reviewNote: 'Customer complaint under review' });
    expect((await post(admin, `${base}/reinstate`)).json()).toMatchObject({ status: 'VERIFIED', reviewNote: null });
    const refused: Array<[string, object | undefined, string]> = [
      ['verify', undefined, 'Only a technician awaiting review can be verified or sent back'],
      ['send-back', { reason: 'x' }, 'Only a technician awaiting review can be verified or sent back'],
      ['reinstate', undefined, 'Only a suspended technician can be reinstated'],
    ];
    for (const [action, payload, message] of refused) {
      const res = await post(admin, `${base}/${action}`, payload);
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ code: 'INVALID_TECHNICIAN_TRANSITION', message });
    }
    const pending = await makeTechnician(['AC'], 'PENDING', [z.id]);
    expect((await post(admin, `/admin/technicians/${pending.technicianId}/suspend`, { reason: 'x' })).json()).toEqual({ code: 'INVALID_TECHNICIAN_TRANSITION', message: 'Only a verified technician can be suspended' });
    expect(await audits(t.technicianId)).toHaveLength(2);
  });

  it('suspend is refused while the technician has an active job; allowed once it is closed', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) })).statusCode).toBe(200);
    const admin = await makeAdminToken();
    const url = `/admin/technicians/${t.technicianId}/suspend`;
    const res = await post(admin, url, { reason: 'x' });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'TECHNICIAN_HAS_ACTIVE_JOB', message: 'This technician has an active job — resolve it before suspending' });
    expect(await statusOf(t.technicianId)).toBe('VERIFIED');
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'CLOSED' } });
    expect((await post(admin, url, { reason: 'x' })).statusCode).toBe(200);
  });

  it('PATCH edits skills/zones in any status, audited by the admin; 404 / 400 / 422 guards', async () => {
    const padra = await zone('Padra');
    const vadodara = await zone('Vadodara');
    const t = await makeTechnician(['AC'], 'VERIFIED', [padra.id]);
    const admin = await makeAdmin();
    const url = `/admin/technicians/${t.technicianId}`;
    const res = await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { skills: ['AC', 'WIRING'], zoneIds: [vadodara.id] } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'VERIFIED', skills: ['AC', 'WIRING'], zones: [{ id: vadodara.id, name: 'Vadodara' }] });
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'PROFILE_UPDATED', subjectId: t.technicianId } });
    expect(audit).toMatchObject({ actorType: 'ADMIN', actorId: admin.userId, metadata: { fields: ['skills', 'zoneIds'], by: 'admin', before: { skills: ['AC'], zoneIds: [padra.id] }, after: { skills: ['AC', 'WIRING'], zoneIds: [vadodara.id] } } });
    // only the edited fields are recorded
    await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { skills: ['FAN'] } });
    const audits2 = await prisma.auditLog.findMany({ where: { action: 'PROFILE_UPDATED', subjectId: t.technicianId }, orderBy: { createdAt: 'desc' } });
    expect(audits2[0]!.metadata).toEqual({ fields: ['skills'], by: 'admin', before: { skills: ['AC', 'WIRING'] }, after: { skills: ['FAN'] } });
    expect((await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: {} })).statusCode).toBe(400);
    expect((await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { name: 'X' } })).statusCode).toBe(400);
    const inactive = await prisma.zone.create({ data: { name: 'Old', visitFeePaise: 9900, status: 'INACTIVE' } });
    expect((await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { zoneIds: [inactive.id] } })).statusCode).toBe(422);
    const missing = '00000000-0000-0000-0000-000000000000';
    expect((await app.inject({ method: 'PATCH', url: `/admin/technicians/${missing}`, headers: auth(admin.token), payload: { skills: ['AC'] } })).statusCode).toBe(404);
    expect((await post(admin.token, `/admin/technicians/${missing}/verify`)).statusCode).toBe(404);
    expect((await post(admin.token, '/admin/technicians/not-a-uuid/verify')).statusCode).toBe(400);
  });
});
