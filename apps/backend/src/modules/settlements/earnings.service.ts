import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { ForbiddenError } from '../../shared/errors.js';
import { payableBalancePaise, splitPaise } from './settlements.service.js';
import { toPayoutRequestDto, type EarningsSummaryDto, type PendingReleaseDto } from './settlements.types.js';

/** The caller's technician row (any status — a suspended technician is still owed their money). */
export async function technicianForUser(userId: string): Promise<{ id: string }> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null }, select: { id: true } });
  if (!t) throw new ForbiddenError('Technician profile required');
  return t;
}

export async function earningsSummary(userId: string): Promise<EarningsSummaryDto> {
  const tech = await technicianForUser(userId);
  // One REPEATABLE READ snapshot: balance, debt, pending and the latest request read in the same transaction.
  return prisma.$transaction(async (tx) => {
    const owedPaise = await payableBalancePaise(tx, tech.id);
    const { cashDebtPaise } = await tx.technician.findUniqueOrThrow({ where: { id: tech.id }, select: { cashDebtPaise: true } });
    const bookings = await tx.booking.findMany({
      where: { technicianId: tech.id, deletedAt: null, state: { in: ['PAYMENT_RECEIVED', 'DISPUTED'] } },
      select: { id: true, bookingNumber: true, state: true, paidAt: true, declinedAt: true, laborPaise: true, visitFeePaise: true, service: { select: { name: true } } },
      orderBy: { paidAt: 'asc' },
    });
    const windowMs = config.DISPUTE_WINDOW_HOURS * 3600_000;
    const pending: PendingReleaseDto[] = bookings.map((b) => {
      const onHold = b.state === 'DISPUTED';
      // The sweep's exact base: the visit fee when the estimate was declined, else labor.
      const base = b.declinedAt != null ? b.visitFeePaise : b.laborPaise;
      return {
        bookingId: b.id, bookingNumber: b.bookingNumber, serviceName: b.service.name,
        amountPaise: splitPaise(base).earningPaise,
        releasesAt: onHold || !b.paidAt ? null : new Date(b.paidAt.getTime() + windowMs).toISOString(),
        onHold,
      };
    });
    const latest = await tx.payoutRequest.findFirst({ where: { technicianId: tech.id }, orderBy: { createdAt: 'desc' } });
    return {
      owedPaise,
      netPayoutPaise: Math.max(0, owedPaise - cashDebtPaise),
      pendingPaise: pending.filter((p) => !p.onHold).reduce((s, p) => s + p.amountPaise, 0),
      cashDebtPaise,
      cashDebtLimitPaise: config.CASH_DEBT_LIMIT_PAISE,
      acceptBlocked: cashDebtPaise > config.CASH_DEBT_LIMIT_PAISE, // the exact rule acceptJob uses
      payoutMinPaise: config.PAYOUT_MIN_PAISE,
      pending,
      latestPayoutRequest: latest ? toPayoutRequestDto(latest) : null,
    };
  }, { isolationLevel: Prisma.TransactionIsolationLevel.RepeatableRead });
}
