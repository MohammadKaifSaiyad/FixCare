import { z } from 'zod';

export const settlementAmountBody = z.object({
  technicianId: z.string().uuid(),
  amountPaise: z.number().int().positive(),
}).strict();
export type SettlementAmountBody = z.infer<typeof settlementAmountBody>;

/** Opaque statement cursor: base64url of `<ISO createdAt>|<entry id>` — (createdAt, id) keeps ties stable. */
export function encodeLedgerCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString('base64url');
}
export function decodeLedgerCursor(cursor: string): { createdAt: Date; id: string } | null {
  const raw = Buffer.from(cursor, 'base64url').toString('utf8');
  const [iso, id, ...rest] = raw.split('|');
  if (!iso || !id || rest.length > 0) return null;
  const createdAt = new Date(iso);
  if (Number.isNaN(createdAt.getTime()) || createdAt.toISOString() !== iso) return null;
  if (!z.string().uuid().safeParse(id).success) return null;
  return { createdAt, id };
}

export const ledgerQuery = z.object({
  limit: z.coerce.number().int().min(1).max(50).default(20),
  before: z.string().min(1).refine((c) => decodeLedgerCursor(c) !== null, 'Invalid cursor').optional(),
}).strict();
export type LedgerQuery = z.infer<typeof ledgerQuery>;

export const payoutRequestIdParams = z.object({ id: z.string().uuid('Invalid payout request id') });
export const listPayoutRequestsQuery = z.object({ status: z.enum(['REQUESTED', 'PAID', 'REJECTED']).optional() }).strict();
/** What ops actually transferred — must equal the amount the server computes under the lock — plus the
 *  bank/UPI transaction reference of that transfer (evidence; Golden Rule 1). Not personal data. */
export const payPayoutRequestBody = z.object({
  amountPaise: z.number().int().positive(),
  transferReference: z.string().trim().min(4, 'transferReference must be 4-64 characters').max(64, 'transferReference must be 4-64 characters')
    .regex(/^[A-Za-z0-9\-\/]+$/, 'transferReference may only contain letters, digits, - and /'),
}).strict();
