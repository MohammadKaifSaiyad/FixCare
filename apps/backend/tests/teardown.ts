import { prisma } from './schema/helpers.js';

export default async function teardown() {
  await prisma.$disconnect();
}
