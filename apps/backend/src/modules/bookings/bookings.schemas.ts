import { z } from 'zod';

export const createBookingBody = z
  .object({
    addressId: z.string().min(1),
    serviceId: z.string().min(1),
    scheduledSlot: z.string().datetime(), // ISO 8601
  })
  .strict()
  .refine((b) => new Date(b.scheduledSlot).getTime() > Date.now(), {
    message: 'scheduledSlot must be in the future',
    path: ['scheduledSlot'],
  });
export type CreateBookingBody = z.infer<typeof createBookingBody>;

export const confirmArrivalBody = z.object({ code: z.string().regex(/^\d{6}$/, 'code must be 6 digits') }).strict();
export type ConfirmArrivalBody = z.infer<typeof confirmArrivalBody>;
