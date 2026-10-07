import { z } from 'zod';

// At least one field required; unknown keys rejected (.strict()).
export const customerPatchBody = z
  .object({ name: z.string().min(1, 'name must not be empty') })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type CustomerPatchBody = z.infer<typeof customerPatchBody>;

// The technician's own patch (name / skills / zones, locked once submitted) lives in the technicians module.
export { technicianPatchBody, type TechnicianPatchBody } from '../technicians/technicians.schemas.js';
