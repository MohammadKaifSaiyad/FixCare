import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { listAvailableJobs, listMyJobs, acceptJob, skipJob, enRouteJob, arriveJob, diagnoseJob, addPart, removePart, signPhotoUpload, confirmPhoto } from './technician-jobs.service.js';
import { arriveBody, diagnoseBody, addPartBody, signPhotoBody, confirmPhotoBody } from './technician-jobs.schemas.js';

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

  app.post('/technician/jobs/:id/en-route', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await enRouteJob(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/technician/jobs/:id/arrive', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = arriveBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await arriveJob(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.post('/technician/jobs/:id/diagnose', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = diagnoseBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await diagnoseJob(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.post('/technician/jobs/:id/parts', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = addPartBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await addPart(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/technician/jobs/:id/parts/:partId', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const { id, partId } = req.params as { id: string; partId: string };
    await removePart(req.user!.id, id, partId);
    return reply.code(204).send();
  });

  app.post('/technician/jobs/:id/photos/sign', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = signPhotoBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await signPhotoUpload(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.post('/technician/jobs/:id/photos', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = confirmPhotoBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await confirmPhoto(req.user!.id, (req.params as { id: string }).id, p.data));
  });
}
