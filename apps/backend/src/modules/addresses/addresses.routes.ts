import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError } from '../../shared/errors.js';
import { serviceabilityQuery } from './addresses.schemas.js';
import { resolvePincode } from './serviceability.service.js';

export async function registerAddressesRoutes(app: FastifyInstance) {
  app.get('/serviceability', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = serviceabilityQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid query');
    return reply.send(await resolvePincode(q.data.pincode));
  });
}
