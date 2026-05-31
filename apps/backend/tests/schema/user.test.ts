import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

describe('User model', () => {
  beforeEach(resetDb);
  afterAll(() => prisma.$disconnect());

  it('creates a user with a unique phone and a role', async () => {
    const u = await prisma.user.create({
      data: { phone: '+919800000001', role: 'CUSTOMER' },
    });
    expect(u.id).toBeTruthy();
    expect(u.status).toBe('ACTIVE');
    expect(u.deletedAt).toBeNull();
  });

  it('rejects a duplicate phone (one role per phone)', async () => {
    await prisma.user.create({ data: { phone: '+919800000002', role: 'CUSTOMER' } });
    await expect(
      prisma.user.create({ data: { phone: '+919800000002', role: 'TECHNICIAN' } })
    ).rejects.toThrow();
  });
});
