import type { Technician } from '@prisma/client';
import { maskPhone } from '../../shared/utils/mask.js';
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

/** Ops' view of a technician. The phone is masked here and nowhere else is it exposed. */
export interface AdminTechnicianDto {
  id: string;
  maskedPhone: string;
  name: string;
  skills: Technician['skills'];
  status: Technician['status'];
  zones: ZoneRef[];
  submittedAt: string | null;
  reviewedAt: string | null;
  reviewNote: string | null;
  createdAt: string;
}

export function toAdminTechnicianDto(t: Technician, phone: string, zones: ZoneRef[]): AdminTechnicianDto {
  return {
    id: t.id, maskedPhone: maskPhone(phone), name: t.name, skills: t.skills, status: t.status, zones,
    submittedAt: t.submittedAt?.toISOString() ?? null, reviewedAt: t.reviewedAt?.toISOString() ?? null,
    reviewNote: t.reviewNote, createdAt: t.createdAt.toISOString(),
  };
}
