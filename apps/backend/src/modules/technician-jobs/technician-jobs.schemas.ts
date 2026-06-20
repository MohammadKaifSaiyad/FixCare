import { z } from 'zod';

export const arriveBody = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
}).strict();
export type ArriveBody = z.infer<typeof arriveBody>;

export const diagnoseBody = z.object({ diagnosedIssueId: z.string().min(1) }).strict();
export type DiagnoseBody = z.infer<typeof diagnoseBody>;

// qty capped at 99 — the unit price is catalog-fixed (Golden Rule 4), so an unbounded qty would be the
// one remaining way a technician could inflate the estimate. 99 of any single part covers a real job.
export const addPartBody = z.object({ partsCatalogId: z.string().min(1), qty: z.number().int().min(1).max(99) }).strict();
export type AddPartBody = z.infer<typeof addPartBody>;
