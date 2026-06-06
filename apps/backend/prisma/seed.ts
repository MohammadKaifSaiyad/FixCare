import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/shared/auth/argon2.js';
import { config } from '../src/shared/config.js';

/** Idempotently create the first SUPER_ADMIN. Exported for tests; run() is the CLI entry. */
export async function seedSuperAdmin(prisma: PrismaClient, email: string, password: string): Promise<void> {
  const existing = await prisma.admin.findUnique({ where: { email } });
  if (existing) {
    console.log(`[seed] admin ${email} already exists — skipping`);
    return;
  }
  const passwordHash = await hashPassword(password);
  await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({ data: { phone: `seed-${Date.now()}`, role: 'ADMIN' } });
    await tx.admin.create({ data: { userId: user.id, name: 'Super Admin', email, passwordHash, adminLevel: 'SUPER_ADMIN' } });
  });
  console.log(`[seed] created SUPER_ADMIN ${email}`);
}

/** Idempotently seed the Vadodara/Padra zones + sample categories/services/prices + parts.
 *  Uses upsert on unique keys so repeated runs do not duplicate. Writes NO audit logs — this is a
 *  one-time system bootstrap, NOT an admin action.
 *
 *  SECURITY (Golden Rule 5): because this bypasses createPart/updatePart, its price upserts are
 *  unaudited. It must NEVER be used to apply production price changes — every production price
 *  mutation must go through the catalog service so PRICE_CHANGED fires. The guard below makes that
 *  machine-enforced: seeding refuses to run unless NODE_ENV is development or test. */
export async function seedCatalog(prisma: PrismaClient): Promise<void> {
  const env = process.env.NODE_ENV;
  if (env !== 'development' && env !== 'test') {
    throw new Error(`seedCatalog must only run in development or test (NODE_ENV=${env ?? 'unset'}) — production/staging price changes must go through the audited catalog service (PRICE_CHANGED), not the seed.`);
  }
  const vadodara = await prisma.zone.upsert({
    where: { name: 'Vadodara' }, update: { visitFeePaise: 14900 },
    create: { name: 'Vadodara', visitFeePaise: 14900 },
  });
  const padra = await prisma.zone.upsert({
    where: { name: 'Padra' }, update: { visitFeePaise: 9900 },
    create: { name: 'Padra', visitFeePaise: 9900 },
  });

  const ac = await prisma.serviceCategory.upsert({ where: { name: 'AC' }, update: {}, create: { name: 'AC' } });
  const fan = await prisma.serviceCategory.upsert({ where: { name: 'Fan' }, update: {}, create: { name: 'Fan' } });

  const gasRefill = await prisma.service.upsert({
    where: { categoryId_name: { categoryId: ac.id, name: 'AC gas refill' } },
    update: {}, create: { categoryId: ac.id, name: 'AC gas refill', tier: 'T2' },
  });
  const fanRepair = await prisma.service.upsert({
    where: { categoryId_name: { categoryId: fan.id, name: 'Ceiling fan repair' } },
    update: {}, create: { categoryId: fan.id, name: 'Ceiling fan repair', tier: 'T1' },
  });

  const prices: Array<{ serviceId: string; zoneId: string; laborPaise: number }> = [
    { serviceId: gasRefill.id, zoneId: vadodara.id, laborPaise: 60000 },
    { serviceId: gasRefill.id, zoneId: padra.id, laborPaise: 50000 },
    { serviceId: fanRepair.id, zoneId: vadodara.id, laborPaise: 25000 },
    { serviceId: fanRepair.id, zoneId: padra.id, laborPaise: 20000 },
  ];
  for (const p of prices) {
    await prisma.servicePrice.upsert({
      where: { serviceId_zoneId: { serviceId: p.serviceId, zoneId: p.zoneId } },
      update: { laborPaise: p.laborPaise },
      create: p,
    });
  }

  const parts: Array<{ sku: string; name: string; categoryId: string; ceilingPricePaise: number }> = [
    { sku: 'AC-GAS-R32-1KG', name: 'R32 refrigerant gas (1kg)', categoryId: ac.id, ceilingPricePaise: 70000 },
    { sku: 'FAN-CAP-2.5MFD', name: 'Fan capacitor 2.5 MFD', categoryId: fan.id, ceilingPricePaise: 12000 },
  ];
  for (const part of parts) {
    await prisma.partsCatalog.upsert({
      where: { sku: part.sku },
      update: { name: part.name, categoryId: part.categoryId, ceilingPricePaise: part.ceilingPricePaise },
      create: part,
    });
  }

  console.log('[seed] catalog: 2 zones, 2 categories, 2 services, 4 prices, 2 parts (idempotent)');
}

async function run(): Promise<void> {
  if (!config.SEED_ADMIN_EMAIL || !config.SEED_ADMIN_PASSWORD) {
    throw new Error('SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD must be set to seed an admin');
  }
  const prisma = new PrismaClient();
  try {
    await seedSuperAdmin(prisma, config.SEED_ADMIN_EMAIL, config.SEED_ADMIN_PASSWORD);
    await seedCatalog(prisma);
  } finally {
    await prisma.$disconnect();
  }
}

const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
  run().catch((err) => { console.error(err); process.exit(1); });
}
