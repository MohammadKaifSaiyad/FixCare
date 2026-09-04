import { describe, expect, it, beforeEach } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { makeCustomer, seedBookable } from '../bookings/helpers.js';

beforeEach(async () => { await resetDb(); });

describe('dispute schema', () => {
  it('one OPEN dispute per booking (partial unique index); a RESOLVED one does not block a new OPEN', async () => {
    const c = await makeCustomer();
    const { zone, service, address, visitFeePaise, laborPaise, zoneName } = await seedBookable(c.customerId);
    const b = await prisma.booking.create({
      data: {
        customerId: c.customerId,
        bookingNumber: `FC-${Date.now()}`,
        state: 'PAYMENT_RECEIVED',
        scheduledSlot: new Date(),
        serviceId: service.id,
        serviceName: service.name,
        zoneId: zone.id,
        zoneName,
        addressId: address.id,
        laborPaise,
        visitFeePaise,
        laborTier: 'T2',
      },
    });
    await prisma.dispute.create({ data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'first' } });
    await expect(prisma.dispute.create({ data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'second' } })).rejects.toThrow();
    await prisma.dispute.updateMany({ where: { bookingId: b.id }, data: { status: 'RESOLVED' } });
    await expect(prisma.dispute.create({ data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'third' } })).resolves.toBeTruthy();
  });
});
