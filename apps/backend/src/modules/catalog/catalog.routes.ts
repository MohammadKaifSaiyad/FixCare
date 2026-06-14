import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ValidationError } from '../../shared/errors.js';
import { createZoneBody, updateZoneBody, createCategoryBody, createServiceBody, upsertPriceBody, partsQuery, createPartBody, updatePartBody, createPincodeBody, updatePincodeBody, createIssueBody, updateIssueBody } from './catalog.schemas.js';
import { listZones, createZone, updateZone, listCategories, createCategory, listServicesByZone, createService, upsertServicePrice, listParts, createPart, updatePart, listPincodes, createPincode, updatePincode, deletePincode, listIssues, createIssue, updateIssue, deleteIssue } from './catalog.service.js';

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

  app.get('/catalog/services', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = req.query as { zoneId?: string; categoryId?: string };
    if (!q.zoneId) throw new ValidationError('zoneId is required');
    return reply.send(await listServicesByZone(q.zoneId, q.categoryId));
  });

  app.post('/catalog/services', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createServiceBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createService(req.user!.id, p.data));
  });

  app.put('/catalog/services/:id/prices/:zoneId', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = upsertPriceBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    const params = req.params as { id: string; zoneId: string };
    return reply.send(await upsertServicePrice(req.user!.id, params.id, params.zoneId, p.data));
  });

  app.get('/catalog/parts', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = partsQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid query');
    return reply.send(await listParts(q.data.categoryId));
  });

  app.post('/catalog/parts', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createPartBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createPart(req.user!.id, p.data));
  });

  app.patch('/catalog/parts/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updatePartBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updatePart(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  // Admin coverage-management view (MANAGER+ per the design) — shows INACTIVE rows too, so they can be
  // found + reactivated. Customers never list the raw map; they use GET /serviceability instead.
  app.get('/catalog/pincodes', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (_req, reply) => reply.send(await listPincodes()));

  app.post('/catalog/pincodes', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createPincodeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createPincode(req.user!.id, p.data));
  });

  app.patch('/catalog/pincodes/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updatePincodeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updatePincode(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/catalog/pincodes/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    await deletePincode(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });

  app.get('/catalog/issues', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = req.query as { categoryId?: string };
    return reply.send(await listIssues(q.categoryId));
  });

  app.post('/catalog/issues', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createIssueBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createIssue(req.user!.id, p.data));
  });

  app.patch('/catalog/issues/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updateIssueBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updateIssue(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/catalog/issues/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    await deleteIssue(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
}
