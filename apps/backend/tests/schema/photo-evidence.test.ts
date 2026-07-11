import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

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

describe('PhotoEvidence model', () => {
  it('stores a diagnosis photo slot with optional geotag and reads back via Booking.photos', async () => {
    const b = await seedBooking();
    await prisma.photoEvidence.create({
      data: { bookingId: b.id, kind: 'DIAGNOSIS_OVERVIEW', r2Key: `jobs/${b.id}/DIAGNOSIS_OVERVIEW-x.jpg`, capturedAt: new Date() },
    });
    const withPhotos = await prisma.booking.findUnique({ where: { id: b.id }, include: { photos: true } });
    expect(withPhotos!.photos).toHaveLength(1);
    expect(withPhotos!.photos[0]!.kind).toBe('DIAGNOSIS_OVERVIEW');
    expect(withPhotos!.photos[0]!.geotagLat).toBeNull();
    expect(withPhotos!.photos[0]!.deletedAt).toBeNull();
  });

  it('soft-delete replace: two rows for one kind, only one active', async () => {
    const b = await seedBooking();
    const first = await prisma.photoEvidence.create({
      data: { bookingId: b.id, kind: 'DIAGNOSIS_CLOSEUP', r2Key: `jobs/${b.id}/DIAGNOSIS_CLOSEUP-a.jpg`, capturedAt: new Date() },
    });
    await prisma.photoEvidence.update({ where: { id: first.id }, data: { deletedAt: new Date() } });
    await prisma.photoEvidence.create({
      data: { bookingId: b.id, kind: 'DIAGNOSIS_CLOSEUP', r2Key: `jobs/${b.id}/DIAGNOSIS_CLOSEUP-b.jpg`, capturedAt: new Date() },
    });
    expect(await prisma.photoEvidence.count({ where: { bookingId: b.id } })).toBe(2);
    expect(await prisma.photoEvidence.count({ where: { bookingId: b.id, deletedAt: null } })).toBe(1);
  });

  it('PHOTO_UPLOADED is a valid audit action', async () => {
    const log = await prisma.auditLog.create({ data: { action: 'PHOTO_UPLOADED', actorType: 'USER', metadata: { kind: 'DIAGNOSIS_OVERVIEW', hasGeotag: false } } });
    expect(log.action).toBe('PHOTO_UPLOADED');
  });
});
