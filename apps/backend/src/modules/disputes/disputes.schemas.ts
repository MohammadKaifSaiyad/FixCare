import { z } from 'zod';

export const raiseDisputeBody = z.object({ reason: z.string().min(1).max(500) }).strict();
export type RaiseDisputeBody = z.infer<typeof raiseDisputeBody>;

export const resolveDisputeBody = z.object({
  outcome: z.enum(['FAVOR_CUSTOMER', 'FAVOR_TECHNICIAN', 'PARTIAL']),
  refundPaise: z.number().int().nonnegative().optional(),
  reason: z.string().min(1).max(500),
}).strict();
export type ResolveDisputeBody = z.infer<typeof resolveDisputeBody>;

export const listDisputesQuery = z.object({
  status: z.enum(['OPEN', 'RESOLVED']).optional(),
}).strict();
export type ListDisputesQuery = z.infer<typeof listDisputesQuery>;
