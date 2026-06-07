import { z } from 'zod';

const paise = z.number().int().min(0, 'must be a non-negative integer (paise)');
const tier = z.enum(['T1', 'T2', 'T3']);

export const createZoneBody = z.object({ name: z.string().min(1), visitFeePaise: paise }).strict();
export type CreateZoneBody = z.infer<typeof createZoneBody>;

export const updateZoneBody = z
  .object({ name: z.string().min(1), visitFeePaise: paise, status: z.enum(['ACTIVE', 'INACTIVE']) })
  .partial().strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdateZoneBody = z.infer<typeof updateZoneBody>;

export const createCategoryBody = z.object({ name: z.string().min(1) }).strict();
export type CreateCategoryBody = z.infer<typeof createCategoryBody>;

export const createServiceBody = z.object({ categoryId: z.string().min(1), name: z.string().min(1), tier }).strict();
export type CreateServiceBody = z.infer<typeof createServiceBody>;

export const upsertPriceBody = z.object({ laborPaise: paise }).strict();
export type UpsertPriceBody = z.infer<typeof upsertPriceBody>;

export const partsQuery = z.object({ categoryId: z.string().min(1).optional() }).strict();
export type PartsQuery = z.infer<typeof partsQuery>;

export const createPartBody = z
  .object({
    sku: z.string().min(1),
    name: z.string().min(1),
    categoryId: z.string().min(1).optional(),
    ceilingPricePaise: paise,
  })
  .strict();
export type CreatePartBody = z.infer<typeof createPartBody>;

export const updatePartBody = z
  .object({
    name: z.string().min(1),
    categoryId: z.string().min(1).nullable(),
    ceilingPricePaise: paise,
    status: z.enum(['ACTIVE', 'INACTIVE']),
  })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdatePartBody = z.infer<typeof updatePartBody>;

const pincode6 = z.string().length(6).regex(/^\d{6}$/, 'pincode must be 6 digits');

export const createPincodeBody = z.object({ pincode: pincode6, zoneId: z.string().min(1) }).strict();
export type CreatePincodeBody = z.infer<typeof createPincodeBody>;

export const updatePincodeBody = z
  .object({ zoneId: z.string().min(1), status: z.enum(['ACTIVE', 'INACTIVE']) })
  .partial().strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdatePincodeBody = z.infer<typeof updatePincodeBody>;
