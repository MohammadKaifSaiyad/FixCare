import { z } from 'zod';

export const raiseDisputeBody = z.object({ reason: z.string().min(1).max(500) }).strict();
export type RaiseDisputeBody = z.infer<typeof raiseDisputeBody>;
