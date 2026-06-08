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
