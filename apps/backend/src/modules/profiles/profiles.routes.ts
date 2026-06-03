import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { getMyProfile } from './profiles.service.js';

export async function registerProfileRoutes(app: FastifyInstance) {
  app.get('/me/profile', { preHandler: [requireAuth] }, async (request, reply) => {
    const result = await getMyProfile(request.user!);
    return reply.code(200).send(result);
  });
}
