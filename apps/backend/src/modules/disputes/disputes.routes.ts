import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { raiseDisputeBody, resolveDisputeBody, listDisputesQuery } from './disputes.schemas.js';
import { raiseDispute, resolveDispute, getDispute, listDisputes } from './disputes.service.js';

function requireCustomerRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'CUSTOMER') throw new ForbiddenError('Only customers can raise disputes');
}

export async function registerDisputeRoutes(app: FastifyInstance): Promise<void> {
  // Customer route: raise a dispute
  app.post('/me/bookings/:id/raise-dispute', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = raiseDisputeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await raiseDispute(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  // Admin routes (all require MANAGER level)
  app.post('/admin/disputes/:id/resolve', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = resolveDisputeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await resolveDispute(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.get('/admin/disputes/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    return reply.send(await getDispute((req.params as { id: string }).id));
  });

  app.get('/admin/disputes', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const q = listDisputesQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid query');
    return reply.send(await listDisputes(q.data.status));
  });
}
