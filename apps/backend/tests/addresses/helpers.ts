import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';
import type { AdminLevel } from '@prisma/client';

let seq = 0;
function uniquePhone(): string { return '9' + String(200000000 + seq++); }

export async function makeCustomerToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return signAccessToken(user.id, 'CUSTOMER');
}

export async function makeAdminToken(level: AdminLevel): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({ data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: level } });
  return signAccessToken(user.id, 'ADMIN');
}

/** Create an ACTIVE zone + an ACTIVE pincode mapping; return the zone. */
export async function seedZoneWithPincode(name: string, visitFeePaise: number, pincode: string) {
  const zone = await prisma.zone.create({ data: { name, visitFeePaise } });
  await prisma.pincodeZone.create({ data: { pincode, zoneId: zone.id } });
  return zone;
}
