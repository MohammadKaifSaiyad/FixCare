import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ValidationError } from '../../shared/errors.js';
import { createZoneBody, updateZoneBody, createCategoryBody } from './catalog.schemas.js';
import { listZones, createZone, updateZone, listCategories, createCategory } from './catalog.service.js';

export async function registerCatalogRoutes(app: FastifyInstance) {
  app.get('/catalog/zones', { preHandler: [requireAuth] }, async (_req, reply) => reply.send(await listZones()));

  app.post('/catalog/zones', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createZoneBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createZone(req.user!.id, p.data));
  });

  app.patch('/catalog/zones/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updateZoneBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updateZone(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.get('/catalog/categories', { preHandler: [requireAuth] }, async (_req, reply) => reply.send(await listCategories()));

  app.post('/catalog/categories', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createCategoryBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createCategory(req.user!.id, p.data));
  });
}
