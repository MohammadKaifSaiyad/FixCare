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

async function run(): Promise<void> {
  if (!config.SEED_ADMIN_EMAIL || !config.SEED_ADMIN_PASSWORD) {
    throw new Error('SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD must be set to seed an admin');
  }
  const prisma = new PrismaClient();
  try {
    await seedSuperAdmin(prisma, config.SEED_ADMIN_EMAIL, config.SEED_ADMIN_PASSWORD);
  } finally {
    await prisma.$disconnect();
  }
}

const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
  run().catch((err) => { console.error(err); process.exit(1); });
}
