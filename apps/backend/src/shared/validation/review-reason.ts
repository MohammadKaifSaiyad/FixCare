import { z } from 'zod';

export const reasonBody = z
  .object({
    reason: z
      .string()
      .trim()
      .min(1, 'reason is required')
      .max(500, 'reason is too long')
      .refine((r) => !/\d{10,}/.test(r.replace(/[\s\-+().]/g, '')), "Don't include phone or ID numbers in the reason")
      .refine((r) => !r.includes('@'), "Don't include UPI IDs or email addresses in the reason"),
  })
  .strict();
