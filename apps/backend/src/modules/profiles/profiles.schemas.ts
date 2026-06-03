import { z } from 'zod';

const serviceSkill = z.enum(['AC', 'FAN', 'ELECTRICAL', 'WIRING', 'APPLIANCE']);

// At least one field required; unknown keys rejected (.strict()).
export const customerPatchBody = z
  .object({ name: z.string().min(1, 'name must not be empty') })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type CustomerPatchBody = z.infer<typeof customerPatchBody>;

export const technicianPatchBody = z
  .object({
    name: z.string().min(1, 'name must not be empty'),
    skills: z.array(serviceSkill).nonempty('skills must not be empty'),
  })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type TechnicianPatchBody = z.infer<typeof technicianPatchBody>;
