import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { raiseDisputeBody } from './disputes.schemas.js';
import { raiseDispute } from './disputes.service.js';

function requireCustomerRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'CUSTOMER') throw new ForbiddenError('Only customers can raise disputes');
}

export async function registerDisputeRoutes(app: FastifyInstance): Promise<void> {
  app.post('/me/bookings/:id/raise-dispute', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = raiseDisputeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await raiseDispute(req.user!.id, (req.params as { id: string }).id, p.data));
  });
}
