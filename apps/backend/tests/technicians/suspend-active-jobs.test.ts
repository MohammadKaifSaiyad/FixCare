import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { BookingState } from '@prisma/client';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Fixture: a VERIFIED technician assigned a booking forced into `state` (the state machine has its own tests). */
async function techWithJobIn(state: BookingState) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
  const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
  const booking = res.json() as { id: string };
  await prisma.booking.update({ where: { id: booking.id }, data: { technicianId: t.technicianId, state } });
  return t;
}
const suspend = (admin: string, technicianId: string) =>
  app.inject({ method: 'POST', url: `/admin/technicians/${technicianId}/suspend`, headers: auth(admin), payload: { reason: 'Test' } });

describe('suspend vs the technician active-job states', () => {
  it.each(['ARRIVED', 'REPAIR_COMPLETE'] as const)('refused with 409 TECHNICIAN_HAS_ACTIVE_JOB while a job is %s', async (state) => {
    const t = await techWithJobIn(state);
    const res = await suspend(await makeAdminToken(), t.technicianId);
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'TECHNICIAN_HAS_ACTIVE_JOB' });
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('VERIFIED');
  });

  it.each(['CUSTOMER_CONFIRMED', 'DECLINED_BY_CUSTOMER', 'PAYMENT_RECEIVED', 'DISPUTED', 'CANCELLED_BY_CUSTOMER'] as const)(
    'allowed while the only assigned job is %s (nothing left for the technician to do)',
    async (state) => {
      const t = await techWithJobIn(state);
      const res = await suspend(await makeAdminToken(), t.technicianId);
      expect(res.statusCode).toBe(200);
      expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('SUSPENDED');
    },
  );
});
