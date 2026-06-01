import type { FastifyInstance } from 'fastify';
import { ValidationError } from '../../shared/errors.js';
import { sendOtpBody, verifyOtpBody } from './auth.schemas.js';
import { sendOtp, verifyOtp } from './auth.service.js';

export async function registerAuthRoutes(app: FastifyInstance) {
  app.post('/auth/otp/send', async (request, reply) => {
    const parsed = sendOtpBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await sendOtp(parsed.data);
    return reply.code(200).send(result);
  });

  app.post('/auth/otp/verify', async (request, reply) => {
    const parsed = verifyOtpBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await verifyOtp(parsed.data);
    return reply.code(200).send(result);
  });
}
