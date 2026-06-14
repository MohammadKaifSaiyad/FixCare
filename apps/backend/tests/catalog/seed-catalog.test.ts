import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { seedCatalog } from '../../prisma/seed.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

describe('seedCatalog', () => {
  it('creates the documented zones, categories, services, prices, and parts', async () => {
    await seedCatalog(prisma);
    const vadodara = await prisma.zone.findUnique({ where: { name: 'Vadodara' } });
    const padra = await prisma.zone.findUnique({ where: { name: 'Padra' } });
    expect(vadodara!.visitFeePaise).toBe(14900);
    expect(padra!.visitFeePaise).toBe(9900);
    expect(await prisma.serviceCategory.count()).toBeGreaterThanOrEqual(2);
    expect(await prisma.service.count()).toBeGreaterThanOrEqual(2);
    expect(await prisma.partsCatalog.count()).toBeGreaterThanOrEqual(2);

    const svc = await prisma.service.findFirst({ where: { name: 'AC gas refill' } });
    const vPrice = await prisma.servicePrice.findUnique({ where: { serviceId_zoneId: { serviceId: svc!.id, zoneId: vadodara!.id } } });
    const pPrice = await prisma.servicePrice.findUnique({ where: { serviceId_zoneId: { serviceId: svc!.id, zoneId: padra!.id } } });
    expect(vPrice!.laborPaise).toBeGreaterThan(0);
    expect(pPrice!.laborPaise).toBeGreaterThan(0);
    expect(vPrice!.laborPaise).not.toBe(pPrice!.laborPaise);

    expect(await prisma.pincodeZone.count()).toBeGreaterThanOrEqual(2);
    const vadoPin = await prisma.pincodeZone.findUnique({ where: { pincode: '390001' } });
    expect(vadoPin!.zoneId).toBe(vadodara!.id);
    const padraPin = await prisma.pincodeZone.findUnique({ where: { pincode: '391440' } });
    expect(padraPin!.zoneId).toBe(padra!.id);

    const acCat = await prisma.serviceCategory.findUnique({ where: { name: 'AC' } });
    expect(await prisma.diagnosedIssue.count({ where: { categoryId: acCat!.id } })).toBeGreaterThanOrEqual(2);
  });

  it('is idempotent — running twice does not duplicate', async () => {
    await seedCatalog(prisma);
    await seedCatalog(prisma);
    expect(await prisma.zone.count()).toBe(2);
    const acCat = await prisma.serviceCategory.count({ where: { name: 'AC' } });
    expect(acCat).toBe(1);
    const svcCount = await prisma.service.count();
    await seedCatalog(prisma);
    expect(await prisma.service.count()).toBe(svcCount);
    expect(await prisma.partsCatalog.count({ where: { sku: 'AC-GAS-R32-1KG' } })).toBe(1);
    expect(await prisma.pincodeZone.count({ where: { pincode: '390001' } })).toBe(1);
  });

  it('does not write audit logs (seed is system bootstrap, not an admin action)', async () => {
    await seedCatalog(prisma);
    expect(await prisma.auditLog.count()).toBe(0);
  });

  it('refuses to run in production (unaudited price writes must never hit prod)', async () => {
    const prev = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    try {
      await expect(seedCatalog(prisma)).rejects.toThrow(/production/);
      expect(await prisma.zone.count()).toBe(0);
    } finally {
      process.env.NODE_ENV = prev;
    }
  });

  it('refuses to run when NODE_ENV is not development/test (e.g. unset or staging)', async () => {
    const prev = process.env.NODE_ENV;
    for (const val of [undefined, 'staging', 'prod']) {
      if (val === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = val;
      try {
        await expect(seedCatalog(prisma)).rejects.toThrow();
        expect(await prisma.zone.count()).toBe(0);
      } finally {
        if (prev === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = prev;
      }
    }
  });
});
