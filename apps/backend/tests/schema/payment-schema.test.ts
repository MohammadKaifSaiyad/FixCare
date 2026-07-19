import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

// Mirrors tests/schema/repair-schema.test.ts's seed — copy that file's seedBooking VERBATIM
// (it has the correct required fields: LaborTier 'T1', Address label, etc.).
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

describe('Payment model', () => {
  it('creates a UPI payment attempt and reads back via Booking.payments', async () => {
    const b = await seedBooking();
    await prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', amountPaise: 45100, razorpayOrderId: 'order_test_1' } });
    const withPayments = await prisma.booking.findUnique({ where: { id: b.id }, include: { payments: true } });
    expect(withPayments!.payments).toHaveLength(1);
    expect(withPayments!.payments[0]!.status).toBe('CREATED');
    expect(withPayments!.payments[0]!.razorpayPaymentId).toBeNull();
  });

  it('razorpayOrderId and razorpayPaymentId are unique (idempotency anchors)', async () => {
    const b = await seedBooking();
    await prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', amountPaise: 100, razorpayOrderId: 'order_dup' } });
    await expect(
      prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', amountPaise: 100, razorpayOrderId: 'order_dup' } }),
    ).rejects.toThrow();
  });

  it('PAYMENT_EVENT is a valid audit action', async () => {
    const log = await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'order_created' } } });
    expect(log.action).toBe('PAYMENT_EVENT');
  });
});
