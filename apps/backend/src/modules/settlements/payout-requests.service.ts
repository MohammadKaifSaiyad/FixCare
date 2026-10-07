import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import type { PayoutRequestStatus } from '@prisma/client';
import { ConflictError, NotFoundError, UnprocessableError } from '../../shared/errors.js';
import { maskPhone } from '../../shared/utils/mask.js';
import { formatPaise } from '../../shared/utils/currency.js';
import { payableBalancePaise } from './settlements.service.js';
import { technicianForUser } from './earnings.service.js';
import { toPayoutRequestDto, type AdminPayoutRequestDto, type PayoutRequestDto } from './settlements.types.js';

/** "₹100" for whole rupees, "₹100.50" otherwise. */
const rupeeLabel = (paise: number) => formatPaise(paise).replace(/\.00$/, '');

/** The technician asks to be paid everything owed, net of the cash they hold. One open request at a time —
 *  enforced under the technician row lock (the same lock recordPayout / pay use), so two taps can't create two. */
export async function requestPayout(userId: string): Promise<PayoutRequestDto> {
  const tech = await technicianForUser(userId);
  // Relies on READ COMMITTED: reads after the row lock see other transactions' commits — never switch this tx to REPEATABLE READ.
  return prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT id FROM "Technician" WHERE id = ${tech.id} FOR UPDATE`;
    const open = await tx.payoutRequest.findFirst({ where: { technicianId: tech.id, status: 'REQUESTED' }, select: { id: true } });
    if (open) throw new ConflictError('You already have a payout request in progress', 'PAYOUT_ALREADY_REQUESTED');
    const owed = await payableBalancePaise(tx, tech.id);
    const { cashDebtPaise } = await tx.technician.findUniqueOrThrow({ where: { id: tech.id }, select: { cashDebtPaise: true } });
    const net = Math.max(0, owed - cashDebtPaise);
    if (net < config.PAYOUT_MIN_PAISE) {
      throw new UnprocessableError(`Payouts start at ${rupeeLabel(config.PAYOUT_MIN_PAISE)}`, 'PAYOUT_BELOW_MINIMUM');
    }
    const created = await tx.payoutRequest.create({ data: { technicianId: tech.id, amountPaise: net } });
    await tx.auditLog.create({
      data: { action: 'SETTLEMENT_EVENT', actorType: 'USER', actorId: userId, subjectId: tech.id, metadata: { event: 'payout_requested', technicianId: tech.id, payoutRequestId: created.id, amountPaise: net } },
    });
    return toPayoutRequestDto(created);
  });
}

const NOT_OPEN = () => new ConflictError('This payout request is no longer open', 'PAYOUT_REQUEST_NOT_OPEN');

async function toAdminDtos(ids: string[]): Promise<AdminPayoutRequestDto[]> {
  const rows = await prisma.payoutRequest.findMany({
    where: { id: { in: ids } },
    include: { technician: { select: { name: true, cashDebtPaise: true, user: { select: { phone: true } } } } },
    orderBy: { createdAt: 'asc' },
  });
  const entryIds = rows.map((r) => r.payoutEntryId).filter((x): x is string => x !== null);
  const entries = await prisma.ledgerEntry.findMany({ where: { id: { in: entryIds } }, select: { id: true, amountPaise: true } });
  const paidById = new Map(entries.map((e) => [e.id, e.amountPaise]));
  const owedByTech = new Map<string, number>();
  for (const techId of new Set(rows.map((r) => r.technicianId))) owedByTech.set(techId, await payableBalancePaise(prisma, techId));
  return rows.map((r) => ({
    ...toPayoutRequestDto(r),
    technicianId: r.technicianId,
    technicianName: r.technician.name,
    maskedPhone: maskPhone(r.technician.user.phone),
    paidPaise: r.payoutEntryId ? paidById.get(r.payoutEntryId) ?? null : null,
    currentOwedPaise: owedByTech.get(r.technicianId) ?? 0,
    currentCashDebtPaise: r.technician.cashDebtPaise,
  }));
}

/** Ops' queue, oldest first. */
export async function listPayoutRequests(status?: PayoutRequestStatus): Promise<AdminPayoutRequestDto[]> {
  const ids = await prisma.payoutRequest.findMany({ where: status ? { status } : {}, orderBy: { createdAt: 'asc' }, select: { id: true } });
  return toAdminDtos(ids.map((r) => r.id));
}

/** Ops transferred the money by hand: net the technician's CURRENT cash debt first (CASH_DEBT_OFFSET, like the
 *  sweep), then record the PAYOUT for the rest, and close the request — one transaction under the technician row
 *  lock. The request row is updated with a status guard, so a racing pay/reject can never both win. */
export async function payPayoutRequest(adminUserId: string, requestId: string): Promise<AdminPayoutRequestDto> {
  // Relies on READ COMMITTED: reads after the row lock see other transactions' commits — never switch this tx to REPEATABLE READ.
  await prisma.$transaction(async (tx) => {
    const req = await tx.payoutRequest.findUnique({ where: { id: requestId }, select: { technicianId: true } });
    if (!req) throw new NotFoundError('Payout request not found');
    await tx.$queryRaw`SELECT id FROM "Technician" WHERE id = ${req.technicianId} FOR UPDATE`;
    const fresh = await tx.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    if (fresh.status !== 'REQUESTED') throw NOT_OPEN();
    const owed = await payableBalancePaise(tx, req.technicianId);
    const { cashDebtPaise } = await tx.technician.findUniqueOrThrow({ where: { id: req.technicianId }, select: { cashDebtPaise: true } });
    const offset = Math.min(Math.max(owed, 0), cashDebtPaise);
    const pay = owed - offset;
    if (pay <= 0) throw new ConflictError('Nothing is owed after settling cash debt — reject this request instead', 'NOTHING_TO_PAY');
    if (offset > 0) {
      await tx.technician.update({ where: { id: req.technicianId }, data: { cashDebtPaise: { decrement: offset } } });
      await tx.ledgerEntry.create({ data: { technicianId: req.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: offset, metadata: { payoutRequestId: requestId } } });
    }
    const entry = await tx.ledgerEntry.create({ data: { technicianId: req.technicianId, type: 'PAYOUT', amountPaise: pay, metadata: { payoutRequestId: requestId } } });
    const closed = await tx.payoutRequest.updateMany({
      where: { id: requestId, status: 'REQUESTED' },
      data: { status: 'PAID', payoutEntryId: entry.id, reviewedBy: adminUserId, reviewedAt: new Date() },
    });
    if (closed.count === 0) throw NOT_OPEN(); // a reject landed in between — roll everything back
    await tx.auditLog.create({
      data: { action: 'SETTLEMENT_EVENT', actorType: 'ADMIN', actorId: adminUserId, subjectId: req.technicianId, metadata: { event: 'payout_request_paid', payoutRequestId: requestId, technicianId: req.technicianId, requestedPaise: fresh.amountPaise, offsetPaise: offset, paidPaise: pay } },
    });
  });
  return (await toAdminDtos([requestId]))[0]!;
}

export async function rejectPayoutRequest(adminUserId: string, requestId: string, reason: string): Promise<AdminPayoutRequestDto> {
  await prisma.$transaction(async (tx) => {
    const req = await tx.payoutRequest.findUnique({ where: { id: requestId }, select: { technicianId: true } });
    if (!req) throw new NotFoundError('Payout request not found');
    const closed = await tx.payoutRequest.updateMany({
      where: { id: requestId, status: 'REQUESTED' },
      data: { status: 'REJECTED', reviewNote: reason, reviewedBy: adminUserId, reviewedAt: new Date() },
    });
    if (closed.count === 0) throw NOT_OPEN();
    await tx.auditLog.create({
      data: { action: 'SETTLEMENT_EVENT', actorType: 'ADMIN', actorId: adminUserId, subjectId: req.technicianId, metadata: { event: 'payout_request_rejected', payoutRequestId: requestId, technicianId: req.technicianId, reason } },
    });
  });
  return (await toAdminDtos([requestId]))[0]!;
}
