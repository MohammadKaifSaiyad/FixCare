import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { ConflictError, UnprocessableError } from '../../shared/errors.js';
import { formatPaise } from '../../shared/utils/currency.js';
import { payableBalancePaise } from './settlements.service.js';
import { technicianForUser } from './earnings.service.js';
import { toPayoutRequestDto, type PayoutRequestDto } from './settlements.types.js';

/** "₹100" for whole rupees, "₹100.50" otherwise. */
const rupeeLabel = (paise: number) => formatPaise(paise).replace(/\.00$/, '');

/** The technician asks to be paid everything owed, net of the cash they hold. One open request at a time —
 *  enforced under the technician row lock (the same lock recordPayout / pay use), so two taps can't create two. */
export async function requestPayout(userId: string): Promise<PayoutRequestDto> {
  const tech = await technicianForUser(userId);
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
