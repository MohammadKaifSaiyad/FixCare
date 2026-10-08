import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { Prisma, type LedgerEntryType, type PayoutRequestStatus } from '@prisma/client';
import { ConflictError, NotFoundError, UnprocessableError } from '../../shared/errors.js';
import { maskPhone } from '../../shared/utils/mask.js';
import { formatPaise } from '../../shared/utils/currency.js';
import { payableBalancePaise } from './settlements.service.js';
import { technicianForUser } from './earnings.service.js';
import { toPayoutRequestDto, type AdminPayoutRequestDto, type PayoutRequestDto } from './settlements.types.js';

/** "₹100" for whole rupees, "₹100.50" otherwise. */
const rupeeLabel = (paise: number) => formatPaise(paise).replace(/\.00$/, '');

/** The technician asks to be paid everything owed, net of the cash they hold. One open request at a time —
 *  enforced under the technician row lock (the same lock pay uses), so two taps can't create two. */
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

const REFERENCE_USED = () => new ConflictError('This transfer reference was already used for another payout', 'TRANSFER_REFERENCE_USED');
const NOT_OPEN = () => new ConflictError('This payout request is no longer open', 'PAYOUT_REQUEST_NOT_OPEN');

async function toAdminDtos(where: Prisma.PayoutRequestWhereInput): Promise<AdminPayoutRequestDto[]> {
  // ONE read-only REPEATABLE READ snapshot: the rows, the technicians' cash debt and every ledger sum come from the
  // same moment, with one groupBy for all technicians (no per-technician balance query).
  return prisma.$transaction(async (tx) => {
    const rows = await tx.payoutRequest.findMany({
      where,
      include: { technician: { select: { name: true, cashDebtPaise: true, status: true, user: { select: { phone: true } } } } },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
    });
    if (rows.length === 0) return [];
    const techIds = [...new Set(rows.map((r) => r.technicianId))];
    const entryIds = rows.map((r) => r.payoutEntryId).filter((x): x is string => x !== null);
    const entries = await tx.ledgerEntry.findMany({ where: { id: { in: entryIds } }, select: { id: true, amountPaise: true } });
    const paidById = new Map(entries.map((e) => [e.id, e.amountPaise]));
    const sums = await tx.ledgerEntry.groupBy({ by: ['technicianId', 'type'], _sum: { amountPaise: true }, where: { technicianId: { in: techIds } } });
    const sumOf = (techId: string, type: LedgerEntryType) => sums.find((x) => x.technicianId === techId && x.type === type)?._sum.amountPaise ?? 0;
    // owed = earnings − offsets − payouts (the same formula as payableBalancePaise)
    const owedOf = (techId: string) => sumOf(techId, 'EARNING_CREDIT') - sumOf(techId, 'CASH_DEBT_OFFSET') - sumOf(techId, 'PAYOUT');
    return rows.map((r) => {
      const owed = owedOf(r.technicianId);
      return {
        ...toPayoutRequestDto(r, r.payoutEntryId ? paidById.get(r.payoutEntryId) ?? null : null),
        technicianId: r.technicianId,
        technicianName: r.technician.name,
        maskedPhone: maskPhone(r.technician.user.phone),
        currentOwedPaise: owed,
        currentCashDebtPaise: r.technician.cashDebtPaise,
        currentNetPaise: Math.max(0, owed - r.technician.cashDebtPaise),
        technicianStatus: r.technician.status,
        transferReference: r.status === 'PAID' ? r.transferReference : null,
      };
    });
  }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
}

/** Ops' queue, oldest first. */
export async function listPayoutRequests(status?: PayoutRequestStatus): Promise<AdminPayoutRequestDto[]> {
  return toAdminDtos(status ? { status } : {});
}

/** Ops transferred the money by hand and records the amount they ACTUALLY sent (0 < amount ≤ the current net).
 *  Under the technician row lock: net the technician's CURRENT cash debt first (CASH_DEBT_OFFSET, like the sweep), then
 *  record a PAYOUT of the transferred amount, and close the request — one transaction. Anything above the net is
 *  refused (a payout can never exceed what is owed); anything below leaves the rest owed. The request row is updated
 *  with a status guard, so a racing pay/reject can never both win. */
export async function payPayoutRequest(adminUserId: string, requestId: string, transferredPaise: number, transferReference: string): Promise<AdminPayoutRequestDto> {
  try {
    // Relies on READ COMMITTED: reads after the row lock see other transactions' commits — never switch this tx to REPEATABLE READ.
    await prisma.$transaction(async (tx) => {
      const req = await tx.payoutRequest.findUnique({ where: { id: requestId }, select: { technicianId: true } });
      if (!req) throw new NotFoundError('Payout request not found');
      await tx.$queryRaw`SELECT id FROM "Technician" WHERE id = ${req.technicianId} FOR UPDATE`;
      const fresh = await tx.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
      if (fresh.status !== 'REQUESTED') throw NOT_OPEN();
      const { cashDebtPaise, deletedAt } = await tx.technician.findUniqueOrThrow({ where: { id: req.technicianId }, select: { cashDebtPaise: true, deletedAt: true } });
      // A removed account is never paid by this path (SUSPENDED / DEACTIVATED still are — ops sees technicianStatus).
      if (deletedAt) throw new ConflictError('This technician account was removed — escalate before paying', 'TECHNICIAN_DELETED');
      const used = await tx.payoutRequest.findFirst({ where: { transferReference }, select: { id: true } });
      if (used) throw REFERENCE_USED();
      const owed = await payableBalancePaise(tx, req.technicianId);
      const offset = Math.min(Math.max(owed, 0), cashDebtPaise);
      const net = owed - offset;
      if (net <= 0) throw new ConflictError('Nothing is owed after settling cash debt — reject this request instead', 'NOTHING_TO_PAY');
      if (transferredPaise > net) {
        throw new ConflictError(`That is more than FixCare owes (${rupeeLabel(net)}) — escalate before recording it`, 'PAYOUT_EXCEEDS_NET');
      }
      if (offset > 0) {
        await tx.technician.update({ where: { id: req.technicianId }, data: { cashDebtPaise: { decrement: offset } } });
        await tx.ledgerEntry.create({ data: { technicianId: req.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: offset, metadata: { payoutRequestId: requestId } } });
      }
      const entry = await tx.ledgerEntry.create({ data: { technicianId: req.technicianId, type: 'PAYOUT', amountPaise: transferredPaise, metadata: { payoutRequestId: requestId } } });
      const closed = await tx.payoutRequest.updateMany({
        where: { id: requestId, status: 'REQUESTED' },
        data: { status: 'PAID', payoutEntryId: entry.id, transferReference, reviewedBy: adminUserId, reviewedAt: new Date() },
      });
      if (closed.count === 0) throw NOT_OPEN(); // a reject landed in between — roll everything back
      await tx.auditLog.create({
        data: { action: 'SETTLEMENT_EVENT', actorType: 'ADMIN', actorId: adminUserId, subjectId: req.technicianId, metadata: { event: 'payout_request_paid', payoutRequestId: requestId, technicianId: req.technicianId, requestedPaise: fresh.amountPaise, offsetPaise: offset, paidPaise: transferredPaise, netPaise: net, transferReference, payoutEntryId: entry.id } },
      });
    });
  } catch (e) {
    // Backstop: the unique index caught a concurrent pay of another request with the same reference (tx rolled back).
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002' && JSON.stringify(e.meta?.target ?? '').includes('transferReference')) throw REFERENCE_USED();
    throw e;
  }
  return (await toAdminDtos({ id: requestId }))[0]!;
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
  return (await toAdminDtos({ id: requestId }))[0]!;
}
