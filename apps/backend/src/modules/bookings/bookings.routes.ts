import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { createBookingBody, confirmArrivalBody } from './bookings.schemas.js';
import { createBooking, listBookings, getBooking, cancelBooking, confirmArrival } from './bookings.service.js';

function requireCustomerRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'CUSTOMER') throw new ForbiddenError('Only customers can book');
}

export async function registerBookingRoutes(app: FastifyInstance) {
  app.post('/me/bookings', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = createBookingBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createBooking(req.user!.id, p.data));
  });

  app.get('/me/bookings', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await listBookings(req.user!.id));
  });

  app.get('/me/bookings/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await getBooking(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/me/bookings/:id/cancel', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await cancelBooking(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/me/bookings/:id/confirm-arrival', { preHandler: [requireAuth] }, async (req, reply) => {
    const p = confirmArrivalBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await confirmArrival(req.user!.id, (req.params as { id: string }).id, p.data));
  });
}
