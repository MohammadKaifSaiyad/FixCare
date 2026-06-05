import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';
import type { AdminLevel } from '@prisma/client';

let seq = 0;
function uniquePhone(): string { return '9' + String(100000000 + seq++); }

/** Create an ADMIN user + Admin profile at the given level; return a Bearer token. */
export async function makeAdminToken(level: AdminLevel): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({
    data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: level },
  });
  return signAccessToken(user.id, 'ADMIN');
}

/** Create a CUSTOMER user + profile; return a Bearer token. */
export async function makeCustomerToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return signAccessToken(user.id, 'CUSTOMER');
}
