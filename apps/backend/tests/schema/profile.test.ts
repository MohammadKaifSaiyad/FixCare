import { beforeEach, describe, expect, it } from 'vitest';
import { Prisma } from '@prisma/client';
import { prisma, resetDb } from './helpers.js';

describe('Role profiles (1:1 with User)', () => {
  beforeEach(resetDb);

  it('links a Technician 1:1 to its User', async () => {
    const user = await prisma.user.create({ data: { phone: '+919800000010', role: 'TECHNICIAN' } });
    const tech = await prisma.technician.create({
      data: { userId: user.id, name: 'Ramesh', skills: ['AC', 'FAN'] },
    });
    expect(tech.status).toBe('PENDING');
    const loaded = await prisma.user.findUnique({ where: { id: user.id }, include: { technician: true } });
    expect(loaded?.technician?.id).toBe(tech.id);
  });

  it('enforces one profile per user (unique userId)', async () => {
    const user = await prisma.user.create({ data: { phone: '+919800000011', role: 'CUSTOMER' } });
    await prisma.customer.create({ data: { userId: user.id, name: 'A' } });
    await expect(
      prisma.customer.create({ data: { userId: user.id, name: 'B' } })
    ).rejects.toThrow(Prisma.PrismaClientKnownRequestError);
  });

  it('stores an Admin with email + passwordHash + adminLevel', async () => {
    const user = await prisma.user.create({ data: { phone: '+919800000012', role: 'ADMIN' } });
    const admin = await prisma.admin.create({
      data: { userId: user.id, name: 'Boss', email: 'boss@fixcare.in', passwordHash: 'argon2-hash', adminLevel: 'SUPER_ADMIN' },
    });
    expect(admin.adminLevel).toBe('SUPER_ADMIN');
  });
});
