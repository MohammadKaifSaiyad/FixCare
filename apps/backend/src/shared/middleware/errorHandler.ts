import type { FastifyInstance, FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { AppError } from '../errors.js';

export function registerErrorHandler(app: FastifyInstance) {
  app.setErrorHandler((err: FastifyError, _req: FastifyRequest, reply: FastifyReply) => {
    if (err instanceof AppError) {
      return reply.code(err.statusCode).send({ code: err.code, message: err.message });
    }
    if (typeof err.statusCode === 'number' && err.statusCode < 500) {
      return reply.code(err.statusCode).send({ code: err.code ?? 'ERROR', message: err.message });
    }
    app.log.error(err);
    return reply.code(500).send({ code: 'INTERNAL_ERROR', message: 'Internal server error' });
  });
}
