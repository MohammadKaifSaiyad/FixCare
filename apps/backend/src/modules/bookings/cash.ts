import type { Prisma, PrismaClient } from '@prisma/client';
import { mintOtp, verifyOtp } from '../../shared/auth/otp-store.js';

// Same knobs as the completion code (10-min TTL, 5 attempts, 3 sends / 15 min — real SMS spend).
const TTL_SECONDS = 600;
const MAX_ATTEMPTS = 5;
const SEND_LIMIT = { max: 3, windowSeconds: 900 };
const key = (bookingId: string) => `cash-receipt:${bookingId}`;

/** Pinned at initiation: the technician can only capture THIS attempt for THIS amount. */
export interface CashReceiptPayload { paymentId: string; amountPaise: number }

export type CashReceiptMint = { status: 'ok'; code: string } | { status: 'throttled' };

/** Mint the single-use cash receipt code to the CUSTOMER. A re-mint replaces any prior code. */
export async function mintCashReceiptCode(bookingId: string, payload: CashReceiptPayload): Promise<CashReceiptMint> {
  return mintOtp(key(bookingId), { ttlSeconds: TTL_SECONDS, sendLimit: SEND_LIMIT }, payload);
}

export type CashReceiptVerify =
  | { status: 'ok'; payload: CashReceiptPayload }
  | { status: 'invalid' }
  | { status: 'no-code' };

/** Verify (and on success consume) the receipt code. Folds like completion-code: exhausted →
 *  'invalid' (probed 5× = auth signal, 401; a fresh customer mint fixes it); 'no-code' covers
 *  never-minted AND expired (409 — the customer re-initiates). */
export async function verifyCashReceiptCode(bookingId: string, code: string): Promise<CashReceiptVerify> {
  const r = await verifyOtp<CashReceiptPayload>(key(bookingId), code, { maxAttempts: MAX_ATTEMPTS });
  switch (r.status) {
    case 'ok': {
      // Malformed payload must fail auth, not crash (the OTP-primitive review lesson). The amount
      // must be a POSITIVE INTEGER: it drives a debt increment and a capture — a zero, negative,
      // or float here (only reachable via a corrupted/foreign Redis write today, but this is a
      // money boundary) would capture with no money moving or silently DECREMENT debt.
      const p = r.payload;
      if (!p || typeof p.paymentId !== 'string' || !Number.isInteger(p.amountPaise) || p.amountPaise <= 0) return { status: 'invalid' };
      return { status: 'ok', payload: p };
    }
    case 'invalid':
    case 'exhausted':
      return { status: 'invalid' };
    case 'no-code':
      return { status: 'no-code' };
    default: {
      const unreachable: never = r;
      throw new Error(`Unhandled verifyOtp status: ${JSON.stringify(unreachable)}`);
    }
  }
}

export const CASH_WINDOW_MS = 24 * 60 * 60 * 1000;

/** Cash this technician CAPTURED in the trailing 24h (velocity-cap input). Works on the client
 *  (initiation UX check) or a tx (post-lock enforcement in the capture). */
export async function cashCollectedLast24hPaise(
  db: Prisma.TransactionClient | PrismaClient,
  technicianId: string,
): Promise<number> {
  const agg = await db.payment.aggregate({
    _sum: { amountPaise: true },
    where: { method: 'CASH', status: 'CAPTURED', capturedAt: { gt: new Date(Date.now() - CASH_WINDOW_MS) }, booking: { technicianId } },
  });
  return agg._sum.amountPaise ?? 0;
}
