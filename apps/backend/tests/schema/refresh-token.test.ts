import { beforeEach, describe, expect, it } from 'vitest';
import { Prisma } from '@prisma/client';
import { prisma, resetDb } from './helpers.js';

describe('RefreshToken model', () => {
  beforeEach(resetDb);

  async function makeUser(phone: string) {
    return prisma.user.create({ data: { phone, role: 'CUSTOMER' } });
  }

  it('stores a hashed token with an expiry', async () => {
    const user = await makeUser('+919800000020');
    const t = await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: 'hash-1', expiresAt: new Date(Date.now() + 30 * 864e5) },
    });
    expect(t.revokedAt).toBeNull();
    expect(t.tokenHash).toBe('hash-1');
  });

  it('links a rotation chain via replacedById', async () => {
    const user = await makeUser('+919800000021');
    const oldT = await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: 'old', expiresAt: new Date(Date.now() + 864e5) },
    });
    const newT = await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: 'new', expiresAt: new Date(Date.now() + 30 * 864e5) },
    });
    const rotated = await prisma.refreshToken.update({
      where: { id: oldT.id },
      data: { revokedAt: new Date(), replacedById: newT.id },
    });
    expect(rotated.replacedById).toBe(newT.id);
  });

  it('rejects a duplicate tokenHash', async () => {
    const user = await makeUser('+919800000022');
    await prisma.refreshToken.create({ data: { userId: user.id, tokenHash: 'dup', expiresAt: new Date(Date.now() + 864e5) } });
    await expect(
      prisma.refreshToken.create({ data: { userId: user.id, tokenHash: 'dup', expiresAt: new Date(Date.now() + 864e5) } })
    ).rejects.toThrow(Prisma.PrismaClientKnownRequestError);
  });
});
