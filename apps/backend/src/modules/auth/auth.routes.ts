import type { FastifyInstance } from 'fastify';
import { ValidationError } from '../../shared/errors.js';
import { sendOtpBody, verifyOtpBody, refreshBody, logoutBody, adminLoginBody } from './auth.schemas.js';
import { sendOtp, verifyOtp, refreshTokens, logout, logoutAll, adminLogin } from './auth.service.js';
import { requireAuth } from '../../shared/middleware/auth.js';

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

  app.post('/auth/refresh', async (request, reply) => {
    const parsed = refreshBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await refreshTokens(parsed.data);
    return reply.code(200).send(result);
  });

  app.post('/auth/logout', async (request, reply) => {
    const parsed = logoutBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    await logout(parsed.data);
    return reply.code(200).send({ ok: true });
  });

  app.post('/auth/logout-all', { preHandler: [requireAuth] }, async (request, reply) => {
    await logoutAll(request.user!.id);
    return reply.code(200).send({ ok: true });
  });

  app.post('/admin/auth/login', async (request, reply) => {
    const parsed = adminLoginBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await adminLogin(parsed.data);
    return reply.code(200).send(result);
  });
}
