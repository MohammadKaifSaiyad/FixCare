import { z } from 'zod';

const pincode = z.string().length(6).regex(/^\d{6}$/, 'pincode must be 6 digits');

export const serviceabilityQuery = z.object({ pincode }).strict();
export type ServiceabilityQuery = z.infer<typeof serviceabilityQuery>;
