import type { Prisma, PrismaClient } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { transitionBooking } from '../bookings/bookings.state.js';

const SWEEP_BATCH = 100;

/** 80/20 split in integer paise. Earning floors; commission takes the remainder so the two
 *  ALWAYS sum exactly to base (no paise ever created or lost — Golden Rule 4 arithmetic). */
export function splitPaise(basePaise: number): { earningPaise: number; commissionPaise: number } {
  const earningPaise = Math.floor((basePaise * (10000 - config.COMMISSION_RATE_BPS)) / 10000);
  return { earningPaise, commissionPaise: basePaise - earningPaise };
}

/** payable = earnings − offsets − payouts. Derived from the ledger alone (reconcilable). */
export async function payableBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number> {
  const sums = await db.ledgerEntry.groupBy({ by: ['type'], _sum: { amountPaise: true }, where: { technicianId } });
  const get = (t: string) => sums.find((s) => s.type === t)?._sum.amountPaise ?? 0;
  return get('EARNING_CREDIT') - get('CASH_DEBT_OFFSET') - get('PAYOUT');
}

/** debt = collected − offsets − repayments. Must equal the cached Technician.cashDebtPaise. */
export async function debtBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number> {
  const sums = await db.ledgerEntry.groupBy({ by: ['type'], _sum: { amountPaise: true }, where: { technicianId } });
  const get = (t: string) => sums.find((s) => s.type === t)?._sum.amountPaise ?? 0;
  return get('CASH_COLLECTED') - get('CASH_DEBT_OFFSET') - get('DEBT_REPAYMENT');
}

/** Called from confirmCashPayment's capture tx: the ledger is the debt source of truth from B6c
 *  on; the Technician.cashDebtPaise increment (same tx, caller's) stays the cached balance. */
export async function recordCashCollected(tx: Prisma.TransactionClient, args: { technicianId: string; bookingId: string; amountPaise: number }): Promise<void> {
  await tx.ledgerEntry.create({ data: { technicianId: args.technicianId, bookingId: args.bookingId, type: 'CASH_COLLECTED', amountPaise: args.amountPaise } });
}

/** Close every PAYMENT_RECEIVED booking whose 48h dispute window has passed, booking the split
 *  and auto-netting cash debt. Idempotent: transitionBooking's optimistic lock makes a double
 *  fire skip. Per-booking try/catch — one failure never aborts the batch. */
export async function settleClosableBookings(now: Date = new Date()): Promise<{ closed: number; skipped: number }> {
  const cutoff = new Date(now.getTime() - config.DISPUTE_WINDOW_HOURS * 3600_000);
  const due = await prisma.booking.findMany({
    where: { state: 'PAYMENT_RECEIVED', deletedAt: null, paidAt: { not: null, lte: cutoff } },
    orderBy: { paidAt: 'asc' },
    take: SWEEP_BATCH,
  });
  let closed = 0;
  let skipped = 0;
  for (const booking of due) {
    try {
      await prisma.$transaction(async (tx) => {
        await transitionBooking(tx, booking, 'CLOSED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'settlement-sweep' });
        if (!booking.technicianId) throw new Error(`paid booking ${booking.id} has no technician`); // data invariant; fail this booking loudly
        const basePaise = booking.declinedAt != null ? booking.visitFeePaise : booking.laborPaise;
        const { earningPaise, commissionPaise } = splitPaise(basePaise);
        const meta = { rateBps: config.COMMISSION_RATE_BPS, basePaise };
        await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'EARNING_CREDIT', amountPaise: earningPaise, metadata: meta } });
        await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'COMMISSION', amountPaise: commissionPaise, metadata: meta } });
        // Auto-net: the technician already HOLDS collected cash — earnings pay the debt down
        // first; payouts only ever move the remainder. Row update = the serializing lock (B6b).
        const tech = await tx.technician.findUniqueOrThrow({ where: { id: booking.technicianId }, select: { cashDebtPaise: true } });
        const offset = Math.min(earningPaise, tech.cashDebtPaise);
        if (offset > 0) {
          await tx.technician.update({ where: { id: booking.technicianId }, data: { cashDebtPaise: { decrement: offset } } });
          await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'CASH_DEBT_OFFSET', amountPaise: offset } });
        }
        // B6b orphan cleanup: an open CASH attempt on a closing booking can never capture now.
        await tx.payment.updateMany({ where: { bookingId: booking.id, method: 'CASH', status: 'CREATED' }, data: { status: 'FAILED', failureReason: 'superseded_at_close' } });
        await tx.booking.update({ where: { id: booking.id }, data: { closedAt: now } });
        await tx.auditLog.create({
          data: { action: 'SETTLEMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'booking_settled', bookingId: booking.id, technicianId: booking.technicianId, earningPaise, commissionPaise, offsetPaise: offset } },
        });
      });
      closed++;
    } catch {
      skipped++; // raced (409) or data problem — next run retries; never abort the batch
    }
  }
  return { closed, skipped };
}
