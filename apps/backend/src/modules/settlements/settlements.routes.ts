import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ValidationError } from '../../shared/errors.js';
import { settlementAmountBody } from './settlements.schemas.js';
import { technicianBalance, recordPayout, recordRepayment, getTechnicianSettlement } from './settlements.service.js';

export async function registerSettlementRoutes(app: FastifyInstance): Promise<void> {
  app.get('/technician/me/balance', { preHandler: [requireAuth] }, async (req, reply) => {
    return reply.send(await technicianBalance(req.user!.id)); // service walls non-technicians (403)
  });

  app.post('/admin/settlements/payouts', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = settlementAmountBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await recordPayout(req.user!.id, p.data));
  });

  app.post('/admin/settlements/repayments', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = settlementAmountBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await recordRepayment(req.user!.id, p.data));
  });

  app.get('/admin/settlements/technicians/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    return reply.send(await getTechnicianSettlement((req.params as { id: string }).id));
  });
}
