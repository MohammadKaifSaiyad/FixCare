import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { seedSuperAdmin } from '../../prisma/seed.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

describe('seedSuperAdmin', () => {
  it('creates a SUPER_ADMIN user + admin profile', async () => {
    await seedSuperAdmin(prisma, 'admin@fixcare.in', 'super-secret-pw');
    const admin = await prisma.admin.findUnique({ where: { email: 'admin@fixcare.in' }, include: { user: true } });
    expect(admin).toBeTruthy();
    expect(admin!.adminLevel).toBe('SUPER_ADMIN');
    expect(admin!.user.role).toBe('ADMIN');
    expect(admin!.passwordHash.startsWith('$argon2id$')).toBe(true);
  });

  it('is idempotent — running twice does not duplicate or throw', async () => {
    await seedSuperAdmin(prisma, 'admin@fixcare.in', 'super-secret-pw');
    await seedSuperAdmin(prisma, 'admin@fixcare.in', 'super-secret-pw');
    const count = await prisma.admin.count({ where: { email: 'admin@fixcare.in' } });
    expect(count).toBe(1);
  });
});
