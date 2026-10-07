import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ForbiddenError, ValidationError } from '../../shared/errors.js';
import { ledgerQuery, settlementAmountBody } from './settlements.schemas.js';
import { earningsSummary, ledgerStatement } from './earnings.service.js';
import { requestPayout } from './payout-requests.service.js';
import { technicianBalance, recordPayout, recordRepayment, getTechnicianSettlement } from './settlements.service.js';

export async function registerSettlementRoutes(app: FastifyInstance): Promise<void> {
  app.get('/technician/me/balance', { preHandler: [requireAuth] }, async (req, reply) => {
    return reply.send(await technicianBalance(req.user!.id)); // service walls non-technicians (403)
  });

  app.get('/technician/me/earnings', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await earningsSummary(req.user!.id));
  });

  app.get('/technician/me/ledger', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    const p = ledgerQuery.safeParse(req.query);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await ledgerStatement(req.user!.id, p.data));
  });

  app.post('/technician/me/payout-requests', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await requestPayout(req.user!.id));
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
