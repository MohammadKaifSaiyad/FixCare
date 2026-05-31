import { PrismaClient } from '@prisma/client';

const testDbUrl = process.env.TEST_DATABASE_URL;
if (!testDbUrl) {
  throw new Error('TEST_DATABASE_URL is not set — refusing to run schema tests against an unknown DB');
}

export const prisma = new PrismaClient({
  datasources: { db: { url: testDbUrl } },
});

// Truncate all tables between tests. Add new tables here as later tasks add models.
export async function resetDb() {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
  );
}
