import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

// Minimal booking seed — mirrors tests/schema/photo-evidence.test.ts (copy its seed idiom
// verbatim if a required field errors; do not change the schema to fit the test).
async function seedBooking() {
  const user = await prisma.user.create({ data: { phone: `98${Math.floor(Math.random() * 1e8)}`, role: 'CUSTOMER' } });
  const customer = await prisma.customer.create({ data: { userId: user.id, name: 'C' } });
  const zone = await prisma.zone.create({ data: { name: `Z-${Math.random().toString(36).slice(2, 8)}`, visitFeePaise: 9900 } });
  const cat = await prisma.serviceCategory.create({ data: { name: `Cat-${Math.random().toString(36).slice(2, 8)}` } });
  const service = await prisma.service.create({ data: { name: 'S', categoryId: cat.id, tier: 'T1', requiredSkill: 'AC' } });
  const address = await prisma.address.create({ data: { customerId: customer.id, label: 'Home', line1: 'L1', pincode: '390001', zoneId: zone.id } });
  return prisma.booking.create({
    data: {
      bookingNumber: `FC-${Math.random().toString(36).slice(2, 8)}`,
      customerId: customer.id, addressId: address.id, serviceId: service.id,
      zoneId: zone.id, zoneName: zone.name, serviceName: service.name,
      visitFeePaise: 9900, laborPaise: 50000, laborTier: 'T1',
      scheduledSlot: new Date(Date.now() + 86_400_000),
    },
  });
}

describe('B5 schema', () => {
  it('accepts the three REPAIR_* photo kinds', async () => {
    const b = await seedBooking();
    for (const kind of ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED'] as const) {
      await prisma.photoEvidence.create({ data: { bookingId: b.id, kind, r2Key: `jobs/${b.id}/${kind}-x.jpg`, capturedAt: new Date() } });
    }
    expect(await prisma.photoEvidence.count({ where: { bookingId: b.id } })).toBe(3);
  });

  it('milestone timestamps are nullable and writable', async () => {
    const b = await seedBooking();
    expect(b.repairStartedAt).toBeNull();
    expect(b.repairCompletedAt).toBeNull();
    expect(b.confirmedAt).toBeNull();
    const updated = await prisma.booking.update({ where: { id: b.id }, data: { repairStartedAt: new Date(), repairCompletedAt: new Date(), confirmedAt: new Date() } });
    expect(updated.confirmedAt).not.toBeNull();
  });
});
