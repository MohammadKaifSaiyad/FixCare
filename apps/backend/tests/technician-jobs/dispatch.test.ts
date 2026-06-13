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

async function book(custToken: string, addressId: string, serviceId: string) {
  return (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(custToken),
    payload: { addressId, serviceId, scheduledSlot: future() } })).json();
}

describe('technician dispatch — available + accept + skip', () => {
  it('a VERIFIED tech with the matching skill sees the open job; masked customer phone, no name', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await book(c.token, f.address.id, f.service.id);
    const t = await makeTechnician(['AC']);
    const res = await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    const jobs = res.json();
    expect(jobs).toHaveLength(1);
    expect(jobs[0].customer.maskedPhone).toMatch(/^•+\d{4}$/);
    expect(JSON.stringify(jobs[0])).not.toContain('Cust'); // no customer name leaked
    expect(jobs[0].address.pincode).toBe(f.pincode);       // address IS shown (needed to service)
  });

  it('wrong-skill tech and unverified tech do not see / cannot act', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // requiredSkill 'AC'
    await book(c.token, f.address.id, f.service.id);
    const fan = await makeTechnician(['FAN']);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(fan.token) })).json()).toHaveLength(0);
    const pending = await makeTechnician(['AC'], 'PENDING');
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(pending.token) })).statusCode).toBe(403);
  });

  it('first-to-accept wins atomically; the loser gets 409; one ACCEPTED audit', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const t1 = await makeTechnician(['AC']);
    const t2 = await makeTechnician(['AC']);
    const [r1, r2] = await Promise.all([
      app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t1.token) }),
      app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t2.token) }),
    ]);
    expect([r1.statusCode, r2.statusCode].sort()).toEqual([200, 409]);
    const updated = await prisma.booking.findUnique({ where: { id: booking.id } });
    expect(updated!.state).toBe('ACCEPTED');
    expect(updated!.technicianId).toBeTruthy();
    const accAudits = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'ACCEPTED' } } });
    expect(accAudits).toHaveLength(1);
  });

  it('an unskilled tech accepting → 403; accepting an already-taken job → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const fan = await makeTechnician(['FAN']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(fan.token) })).statusCode).toBe(403);
    const ac1 = await makeTechnician(['AC']);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(ac1.token) });
    const ac2 = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(ac2.token) })).statusCode).toBe(409);
  });

  it('skip hides the job from that tech only; idempotent; others still see it', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const t1 = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/skip`, headers: auth(t1.token) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/skip`, headers: auth(t1.token) })).statusCode).toBe(204); // idempotent
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t1.token) })).json()).toHaveLength(0);
    const t2 = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t2.token) })).json()).toHaveLength(1);
  });

  it('mine returns the tech\'s accepted jobs; non-technician → 403', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const t = await makeTechnician(['AC']);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).json()).toHaveLength(1);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(c.token) })).statusCode).toBe(403); // customer
  });
});
