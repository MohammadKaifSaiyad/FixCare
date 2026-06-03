import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError } from '../../shared/errors.js';
import { customerPatchBody, technicianPatchBody } from './profiles.schemas.js';
import { getMyProfile, updateMyProfile } from './profiles.service.js';

export async function registerProfileRoutes(app: FastifyInstance) {
  app.get('/me/profile', { preHandler: [requireAuth] }, async (request, reply) => {
    const result = await getMyProfile(request.user!);
    return reply.code(200).send(result);
  });

  app.patch('/me/profile', { preHandler: [requireAuth] }, async (request, reply) => {
    const user = request.user!;
    const schema = user.role === 'TECHNICIAN' ? technicianPatchBody : customerPatchBody;
    const parsed = schema.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await updateMyProfile(user, parsed.data);
    return reply.code(200).send(result);
  });
}
