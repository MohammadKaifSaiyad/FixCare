import { z } from 'zod';

export const serviceSkill = z.enum(['AC', 'FAN', 'ELECTRICAL', 'WIRING', 'APPLIANCE']);
const unique = <T>(a: readonly T[]) => new Set(a).size === a.length;

export const nameField = z.string().trim().min(1, 'name must not be empty').max(80, 'name is too long');
export const skillsField = z.array(serviceSkill).nonempty('skills must not be empty').refine(unique, 'skills must not repeat');
export const zoneIdsField = z.array(z.string().uuid('zoneIds must be zone ids')).nonempty('zoneIds must not be empty').refine(unique, 'zoneIds must not repeat');

// The technician's own PATCH /me/profile. At least one field; unknown keys rejected. Declared in this order
// on purpose — the audit row's `fields` follow it.
export const technicianPatchBody = z
  .object({ name: nameField, skills: skillsField, zoneIds: zoneIdsField })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type TechnicianPatchBody = z.infer<typeof technicianPatchBody>;

export const technicianIdParams = z.object({ id: z.string().uuid('Invalid technician id') });

export const listTechniciansQuery = z
  .object({ status: z.enum(['PENDING', 'KYC_SUBMITTED', 'VERIFIED', 'SUSPENDED', 'DEACTIVATED']).optional() })
  .strict();

export const reasonBody = z.object({ reason: z.string().trim().min(1, 'reason is required').max(500, 'reason is too long') }).strict();

export const adminTechnicianPatchBody = z
  .object({ skills: skillsField, zoneIds: zoneIdsField })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type AdminTechnicianPatchBody = z.infer<typeof adminTechnicianPatchBody>;
