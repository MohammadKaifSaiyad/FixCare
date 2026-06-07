import { z } from 'zod';

const pincode = z.string().length(6).regex(/^\d{6}$/, 'pincode must be 6 digits');

export const serviceabilityQuery = z.object({ pincode }).strict();
export type ServiceabilityQuery = z.infer<typeof serviceabilityQuery>;

const latLng = {
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
};

export const createAddressBody = z
  .object({
    label: z.string().min(1),
    line1: z.string().min(1),
    line2: z.string().min(1).optional(),
    landmark: z.string().min(1).optional(),
    pincode,
    lat: latLng.lat.optional(),
    lng: latLng.lng.optional(),
    isDefault: z.boolean().optional(),
  })
  .strict()
  .refine((b) => (b.lat === undefined) === (b.lng === undefined), {
    message: 'lat and lng must be provided together',
  });
export type CreateAddressBody = z.infer<typeof createAddressBody>;

export const updateAddressBody = z
  .object({
    label: z.string().min(1),
    line1: z.string().min(1),
    line2: z.string().min(1).nullable(),
    landmark: z.string().min(1).nullable(),
    pincode,
    lat: latLng.lat.nullable(),
    lng: latLng.lng.nullable(),
    isDefault: z.boolean(),
  })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' })
  .refine((b) => !('lat' in b || 'lng' in b) || ('lat' in b) === ('lng' in b), {
    message: 'lat and lng must be updated together',
  });
export type UpdateAddressBody = z.infer<typeof updateAddressBody>;
