import { Prisma, type PrismaClient, type LedgerEntryType } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import { NotFoundError, ConflictError, ForbiddenError } from '../../shared/errors.js';

const SWEEP_BATCH = 100;

/** 80/20 split in integer paise. Earning floors; commission takes the remainder so the two
 *  ALWAYS sum exactly to base (no paise ever created or lost — Golden Rule 4 arithmetic). */
export function splitPaise(basePaise: number): { earningPaise: number; commissionPaise: number } {
  const earningPaise = Math.floor((basePaise * (10000 - config.COMMISSION_RATE_BPS)) / 10000);
  return { earningPaise, commissionPaise: basePaise - earningPaise };
}

/** One groupBy → per-type sum map. The lookup key is LedgerEntryType (not string) so a typo can't
 *  compile to a silent 0. Callers that need BOTH balances share ONE query — and, run inside a tx,
 *  a consistent snapshot (so payable and debt can't be read from two different moments). */
async function sumLedgerByType(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<(t: LedgerEntryType) => number> {
  const sums = await db.ledgerEntry.groupBy({ by: ['type'], _sum: { amountPaise: true }, where: { technicianId } });
  return (t: LedgerEntryType) => sums.find((s) => s.type === t)?._sum.amountPaise ?? 0;
}

/** payable = earnings − offsets − payouts. Derived from the ledger alone (reconcilable). */
export async function payableBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number> {
  const get = await sumLedgerByType(db, technicianId);
  return get('EARNING_CREDIT') - get('CASH_DEBT_OFFSET') - get('PAYOUT');
}

/** debt = collected − offsets − repayments. Must equal the cached Technician.cashDebtPaise. */
export async function debtBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number> {
  const get = await sumLedgerByType(db, technicianId);
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
        if (!booking.technicianId) throw new Error(`paid booking ${booking.id} has no technician`); // data invariant; fail this booking loudly
        const basePaise = booking.declinedAt != null ? booking.visitFeePaise : booking.laborPaise;
        await transitionBooking(tx, booking, 'CLOSED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'settlement-sweep' });
        const { earningPaise, commissionPaise } = splitPaise(basePaise);
        const meta = { rateBps: config.COMMISSION_RATE_BPS, basePaise };
        // amountPaise is "always POSITIVE" — a zero-priced service (catalog allows 0 labor/visit fee)
        // would otherwise write 0-amount rows that corrupt the invariant and could break a future
        // Route transfer. Skip the entry when its amount is 0; the booking still CLOSEs.
        if (earningPaise > 0) await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'EARNING_CREDIT', amountPaise: earningPaise, metadata: meta } });
        if (commissionPaise > 0) await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'COMMISSION', amountPaise: commissionPaise, metadata: meta } });
        // Auto-net: the technician already HOLDS collected cash — earnings pay the debt down
        // first; payouts only ever move the remainder. FOR UPDATE acquires the row lock BEFORE
        // reading, serializing concurrent same-technician settlements across parallel sweep runners.
        const [locked] = await tx.$queryRaw<{ cashDebtPaise: number }[]>`SELECT "cashDebtPaise" FROM "Technician" WHERE id = ${booking.technicianId} FOR UPDATE`;
        if (!locked) throw new Error(`technician ${booking.technicianId} vanished mid-settlement`); // fail LOUD (→ skipped) rather than silently skip the debt offset
        const currentDebt = Number(locked.cashDebtPaise);
        const offset = Math.min(earningPaise, currentDebt);
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
    } catch (err) {
      skipped++; // raced (409) or data problem — next run retries; never abort the batch
      console.error('settlement sweep error', { bookingId: booking.id }, err instanceof Error ? err.message : err);
    }
  }
  return { closed, skipped };
}

/** Technician dashboard balance. Payable derives from the ledger; debt is the cached column.
 *  If the ledger-derived debt disagrees with the cache, flag it loudly (reconciliation) but
 *  return the CACHED value — it is what the gates enforce. */
export async function technicianBalance(userId: string): Promise<{ payablePaise: number; cashDebtPaise: number }> {
  const tech = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!tech) throw new ForbiddenError('Technician profile required');
  // ONE snapshot: the cached column and both ledger balances must be read from the SAME moment,
  // or a concurrent capture/settlement committing mid-read fires a FALSE reconciliation mismatch.
  const { cashDebtPaise, payablePaise, ledgerDebt } = await prisma.$transaction(async (tx) => {
    const row = await tx.technician.findUniqueOrThrow({ where: { id: tech.id }, select: { cashDebtPaise: true } });
    const get = await sumLedgerByType(tx, tech.id);
    return {
      cashDebtPaise: row.cashDebtPaise,
      payablePaise: get('EARNING_CREDIT') - get('CASH_DEBT_OFFSET') - get('PAYOUT'),
      ledgerDebt: get('CASH_COLLECTED') - get('CASH_DEBT_OFFSET') - get('DEBT_REPAYMENT'),
    };
  });
  if (ledgerDebt !== cashDebtPaise) {
    // Pre-B6c cash captures wrote no CASH_COLLECTED entries, so a mismatch is expected for
    // migrated technicians — flagged, not fatal. Best-effort: a failed flag write must NOT 500 a
    // read whose balance computed fine (the flag is diagnostic, not the response).
    await prisma.auditLog.create({ data: { action: 'SETTLEMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'reconciliation_mismatch', technicianId: tech.id, cachedPaise: cashDebtPaise, ledgerPaise: ledgerDebt } } })
      .catch((e) => console.error('reconciliation flag write failed', { technicianId: tech.id }, e instanceof Error ? e.message : e));
  }
  return { payablePaise, cashDebtPaise };
}

async function technicianOrThrow(technicianId: string) {
  const t = await prisma.technician.findFirst({ where: { id: technicianId, deletedAt: null } });
  if (!t) throw new NotFoundError('Technician not found');
  return t;
}

/** Manual payout record (until Razorpay Route): money the founder actually transferred. */
export async function recordPayout(adminUserId: string, body: { technicianId: string; amountPaise: number }): Promise<{ id: string }> {
  await technicianOrThrow(body.technicianId);
  return prisma.$transaction(async (tx) => {
    // Lock the technician row BEFORE reading the ledger payable: unlike cashDebtPaise, payable has
    // no CHECK backstop, so two concurrent payouts must not each pass the guard and jointly overdraw.
    await tx.$queryRaw`SELECT id FROM "Technician" WHERE id = ${body.technicianId} FOR UPDATE`;
    const payable = await payableBalancePaise(tx, body.technicianId);
    if (body.amountPaise > payable) throw new ConflictError('Amount exceeds the payable balance');
    const entry = await tx.ledgerEntry.create({ data: { technicianId: body.technicianId, type: 'PAYOUT', amountPaise: body.amountPaise } });
    await tx.auditLog.create({ data: { action: 'SETTLEMENT_EVENT', actorType: 'USER', actorId: adminUserId, metadata: { event: 'payout_recorded', technicianId: body.technicianId, amountPaise: body.amountPaise } } });
    return { id: entry.id };
  });
}

/** Manual cash-repayment record: the technician handed collected cash back to the platform. */
export async function recordRepayment(adminUserId: string, body: { technicianId: string; amountPaise: number }): Promise<{ id: string }> {
  await technicianOrThrow(body.technicianId);
  return prisma.$transaction(async (tx) => {
    // Row update first = the serializing lock (B6b idiom). Postgres raises the CHECK (>= 0) BEFORE
    // any JS guard when the repayment exceeds the debt. Prisma surfaces that pg 23514 as an
    // UNKNOWN request error (verified: Known errors like P2025 and connection failures are distinct
    // classes) — narrow the catch to it so only "over-debt" becomes 409; real outages re-throw → 500.
    try {
      await tx.technician.update({ where: { id: body.technicianId }, data: { cashDebtPaise: { decrement: body.amountPaise } }, select: { cashDebtPaise: true } });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientUnknownRequestError) throw new ConflictError('Amount exceeds the outstanding debt');
      throw e;
    }
    const entry = await tx.ledgerEntry.create({ data: { technicianId: body.technicianId, type: 'DEBT_REPAYMENT', amountPaise: body.amountPaise } });
    await tx.auditLog.create({ data: { action: 'SETTLEMENT_EVENT', actorType: 'USER', actorId: adminUserId, metadata: { event: 'repayment_recorded', technicianId: body.technicianId, amountPaise: body.amountPaise } } });
    return { id: entry.id };
  });
}

/** Admin drill-down: balances + recent entries, newest first. */
export async function getTechnicianSettlement(technicianId: string): Promise<{ payablePaise: number; cashDebtPaise: number; entries: { type: string; amountPaise: number; bookingId: string | null; createdAt: string }[] }> {
  const t = await technicianOrThrow(technicianId);
  const [payablePaise, rows] = await Promise.all([
    payableBalancePaise(prisma, technicianId),
    prisma.ledgerEntry.findMany({ where: { technicianId }, orderBy: { createdAt: 'desc' }, take: 50 }),
  ]);
  return { payablePaise, cashDebtPaise: t.cashDebtPaise, entries: rows.map((e) => ({ type: e.type, amountPaise: e.amountPaise, bookingId: e.bookingId, createdAt: e.createdAt.toISOString() })) };
}
