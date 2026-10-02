import type { FastifyInstance } from 'fastify';
import type { z } from 'zod';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ForbiddenError, ValidationError } from '../../shared/errors.js';
import { adminTechnicianPatchBody, listTechniciansQuery, reasonBody, technicianIdParams } from './technicians.schemas.js';
import { adminUpdateTechnician, listTechnicians, reviewTechnician, submitForReview } from './technicians.service.js';

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const p = schema.safeParse(value);
  if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
  return p.data;
}

export async function registerTechnicianRoutes(app: FastifyInstance): Promise<void> {
  // Technician-role only — NOT the VERIFIED gate (submitting is how a technician gets verified).
  app.post('/technician/me/submit', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await submitForReview(req.user!.id));
  });

  const manager = { preHandler: [requireAuth, requireAdminLevel('MANAGER')] };

  app.get('/admin/technicians', manager, async (req, reply) => {
    const { status } = parse(listTechniciansQuery, req.query);
    return reply.send(await listTechnicians(status));
  });

  app.post('/admin/technicians/:id/verify', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    return reply.send(await reviewTechnician(req.user!.id, id, 'verify'));
  });

  app.post('/admin/technicians/:id/send-back', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    const { reason } = parse(reasonBody, req.body);
    return reply.send(await reviewTechnician(req.user!.id, id, 'sendBack', reason));
  });

  app.post('/admin/technicians/:id/suspend', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    const { reason } = parse(reasonBody, req.body);
    return reply.send(await reviewTechnician(req.user!.id, id, 'suspend', reason));
  });

  app.post('/admin/technicians/:id/reinstate', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    return reply.send(await reviewTechnician(req.user!.id, id, 'reinstate'));
  });

  app.patch('/admin/technicians/:id', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    const body = parse(adminTechnicianPatchBody, req.body);
    return reply.send(await adminUpdateTechnician(req.user!.id, id, body));
  });
}
