import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ForbiddenError } from '../../shared/errors.js';
import { submitForReview } from './technicians.service.js';

export async function registerTechnicianRoutes(app: FastifyInstance): Promise<void> {
  // Technician-role only — NOT the VERIFIED gate (submitting is how a technician gets verified).
  app.post('/technician/me/submit', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await submitForReview(req.user!.id));
  });
}
