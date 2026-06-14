import { z } from 'zod';

export const arriveBody = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
}).strict();
export type ArriveBody = z.infer<typeof arriveBody>;

export const diagnoseBody = z.object({ diagnosedIssueId: z.string().min(1) }).strict();
export type DiagnoseBody = z.infer<typeof diagnoseBody>;

export const addPartBody = z.object({ partsCatalogId: z.string().min(1), qty: z.number().int().min(1) }).strict();
export type AddPartBody = z.infer<typeof addPartBody>;
