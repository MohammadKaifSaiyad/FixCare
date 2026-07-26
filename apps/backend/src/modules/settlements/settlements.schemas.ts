import { z } from 'zod';

export const settlementAmountBody = z.object({
  technicianId: z.string().uuid(),
  amountPaise: z.number().int().positive(),
}).strict();
export type SettlementAmountBody = z.infer<typeof settlementAmountBody>;
