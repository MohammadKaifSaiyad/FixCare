import { beforeEach, describe, expect, it } from 'vitest';
import { Prisma } from '@prisma/client';
import { prisma, resetDb } from './helpers.js';

describe('User model', () => {
  beforeEach(resetDb);

  it('creates a user with a unique phone and a role', async () => {
    const u = await prisma.user.create({
      data: { phone: '+919800000001', role: 'CUSTOMER' },
    });
    expect(u.id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    expect(u.status).toBe('ACTIVE');
    expect(u.deletedAt).toBeNull();
  });

  it('rejects a duplicate phone (one role per phone)', async () => {
    await prisma.user.create({ data: { phone: '+919800000002', role: 'CUSTOMER' } });
    await expect(
      prisma.user.create({ data: { phone: '+919800000002', role: 'TECHNICIAN' } })
    ).rejects.toThrow(Prisma.PrismaClientKnownRequestError);
  });
});
