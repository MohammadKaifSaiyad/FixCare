import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ForbiddenError } from '../../shared/errors.js';
import { listAvailableJobs, listMyJobs, acceptJob, skipJob } from './technician-jobs.service.js';

function requireTechnicianRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
}

export async function registerTechnicianJobRoutes(app: FastifyInstance) {
  app.get('/technician/jobs/available', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await listAvailableJobs(req.user!.id));
  });

  app.get('/technician/jobs/mine', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await listMyJobs(req.user!.id));
  });

  app.post('/technician/jobs/:id/accept', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await acceptJob(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/technician/jobs/:id/skip', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    await skipJob(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
}
