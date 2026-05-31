import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient({
  datasources: { db: { url: process.env.TEST_DATABASE_URL } },
});

// Truncate all tables between tests. Add new tables here as later tasks add models.
export async function resetDb() {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "User" RESTART IDENTITY CASCADE;'
  );
}
