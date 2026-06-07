import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { serviceabilityQuery, createAddressBody, updateAddressBody } from './addresses.schemas.js';
import { resolvePincode } from './serviceability.service.js';
import { listAddresses, createAddress, getAddress, updateAddress, deleteAddress } from './addresses.service.js';

function requireCustomerRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'CUSTOMER') throw new ForbiddenError('Only customers have addresses');
}

export async function registerAddressesRoutes(app: FastifyInstance) {
  app.get('/serviceability', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = serviceabilityQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid query');
    return reply.send(await resolvePincode(q.data.pincode));
  });

  app.get('/me/addresses', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await listAddresses(req.user!.id));
  });

  app.post('/me/addresses', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = createAddressBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createAddress(req.user!.id, p.data));
  });

  app.get('/me/addresses/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await getAddress(req.user!.id, (req.params as { id: string }).id));
  });

  app.patch('/me/addresses/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = updateAddressBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updateAddress(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/me/addresses/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    await deleteAddress(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
}
