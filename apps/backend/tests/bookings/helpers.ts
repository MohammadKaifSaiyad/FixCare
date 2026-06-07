import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';

let seq = 0;
function uniquePhone(): string { return '9' + String(300000000 + seq++); }

export async function makeCustomer(): Promise<{ token: string; userId: string; customerId: string }> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  const c = await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return { token: signAccessToken(user.id, 'CUSTOMER'), userId: user.id, customerId: c.id };
}

export async function makeAdminToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({ data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: 'MANAGER' } });
  return signAccessToken(user.id, 'ADMIN');
}

/** Seed a serviceable happy-path: zone+visitFee, a service priced in that zone, a pincode→zone
 *  mapping, and an address (owned by customerId) in that pincode. */
export async function seedBookable(customerId: string, opts?: { visitFeePaise?: number; laborPaise?: number }) {
  const visitFeePaise = opts?.visitFeePaise ?? 14900;
  const laborPaise = opts?.laborPaise ?? 60000;
  const zone = await prisma.zone.create({ data: { name: 'Vadodara', visitFeePaise } });
  const cat = await prisma.serviceCategory.create({ data: { name: 'AC' } });
  const service = await prisma.service.create({ data: { categoryId: cat.id, name: 'AC gas refill', tier: 'T2' } });
  await prisma.servicePrice.create({ data: { serviceId: service.id, zoneId: zone.id, laborPaise } });
  await prisma.pincodeZone.create({ data: { pincode: '390001', zoneId: zone.id } });
  const address = await prisma.address.create({
    data: { customerId, label: 'Home', line1: '12 MG Road', pincode: '390001', zoneId: zone.id, isDefault: true },
  });
  return { zone, cat, service, address, visitFeePaise, laborPaise };
}
