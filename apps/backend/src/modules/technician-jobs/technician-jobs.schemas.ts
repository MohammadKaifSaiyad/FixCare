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

export const photoKind = z.enum(['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']);

// contentLengthBytes is signed into the presigned PUT — this IS the 1MB cap (jpeg-only is pinned
// server-side; the client never chooses the Content-Type).
export const signPhotoBody = z.object({
  kind: photoKind,
  contentLengthBytes: z.number().int().min(1).max(1_048_576),
}).strict();
export type SignPhotoBody = z.infer<typeof signPhotoBody>;

export const confirmPhotoBody = z.object({
  kind: photoKind,
  key: z.string().min(1),
  capturedAt: z.string().datetime(), // ISO 8601
  geotagLat: z.number().min(-90).max(90).optional(),
  geotagLng: z.number().min(-180).max(180).optional(),
}).strict().refine((b) => (b.geotagLat === undefined) === (b.geotagLng === undefined), {
  message: 'geotagLat and geotagLng must be provided together',
});
export type ConfirmPhotoBody = z.infer<typeof confirmPhotoBody>;
