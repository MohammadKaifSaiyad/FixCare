import type { FastifyInstance } from 'fastify';
import { ValidationError } from '../../shared/errors.js';
import { sendOtpBody } from './auth.schemas.js';
import { sendOtp } from './auth.service.js';

export async function registerAuthRoutes(app: FastifyInstance) {
  app.post('/auth/otp/send', async (request, reply) => {
    const parsed = sendOtpBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await sendOtp(parsed.data);
    return reply.code(200).send(result);
  });
}
