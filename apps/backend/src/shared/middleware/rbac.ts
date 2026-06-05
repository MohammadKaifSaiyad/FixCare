import type { FastifyReply, FastifyRequest } from 'fastify';
import type { AdminLevel } from '@prisma/client';
import { prisma } from '../database/prisma.js';
import { ForbiddenError } from '../errors.js';

const RANK: Record<AdminLevel, number> = { SUPPORT: 1, MANAGER: 2, SUPER_ADMIN: 3 };

/** Fastify preHandler (run AFTER requireAuth): require the caller be an admin of at least `min` level. */
export function requireAdminLevel(min: AdminLevel) {
  return async function (request: FastifyRequest, _reply: FastifyReply): Promise<void> {
    const user = request.user;
    if (!user || user.role !== 'ADMIN') throw new ForbiddenError('Admin access required');
    const admin = await prisma.admin.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!admin || admin.status !== 'ACTIVE') throw new ForbiddenError('Admin access required');
    if (RANK[admin.adminLevel] < RANK[min]) throw new ForbiddenError('Insufficient admin level');
  };
}
