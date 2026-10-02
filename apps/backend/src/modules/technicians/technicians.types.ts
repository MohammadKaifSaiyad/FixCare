import type { Technician } from '@prisma/client';
import type { ZoneRef } from '../catalog/catalog.types.js';

/** The technician's own view of their profile (GET/PATCH /me/profile, POST /technician/me/submit). */
export interface TechnicianProfileDto {
  id: string;
  role: 'TECHNICIAN';
  name: string;
  skills: Technician['skills'];
  status: Technician['status'];
  zones: ZoneRef[];
  /** Ops' reason when the profile was sent back or the account suspended; null otherwise. */
  reviewNote: string | null;
  submittedAt: string | null;
}

export function toTechnicianProfileDto(t: Technician, zones: ZoneRef[]): TechnicianProfileDto {
  return {
    id: t.id, role: 'TECHNICIAN', name: t.name, skills: t.skills, status: t.status, zones,
    reviewNote: t.reviewNote, submittedAt: t.submittedAt?.toISOString() ?? null,
  };
}
