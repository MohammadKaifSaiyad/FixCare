import { prisma } from './schema/helpers.js';
import { redis } from '../src/shared/redis/client.js';

export default async function teardown() {
  await prisma.$disconnect();
  await redis.quit();
}
