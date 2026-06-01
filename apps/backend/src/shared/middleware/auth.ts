import type { FastifyReply, FastifyRequest } from 'fastify';
import type { UserRole } from '@prisma/client';
import { verifyAccessToken } from '../auth/tokens.js';
import { prisma } from '../database/prisma.js';
import { UnauthorizedError, ForbiddenError } from '../errors.js';

declare module 'fastify' {
  interface FastifyRequest {
    user?: { id: string; role: UserRole };
  }
}

/** Fastify preHandler: verify Bearer JWT, load the user, reject suspended/deleted. */
export async function requireAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw new UnauthorizedError('Missing bearer token');
  const claims = verifyAccessToken(header.slice('Bearer '.length));

  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user || user.deletedAt) throw new UnauthorizedError('Invalid token');
  if (user.status !== 'ACTIVE') throw new ForbiddenError('Account is not active');

  request.user = { id: user.id, role: user.role };
}

/** Throw if the authenticated user does not own the target resource. */
export function assertOwnership(user: { id: string }, resourceUserId: string): void {
  if (user.id !== resourceUserId) throw new ForbiddenError('You do not have access to this resource');
}
