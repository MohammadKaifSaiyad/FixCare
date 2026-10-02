import { prisma } from '../../shared/database/prisma.js';
import type { UserRole } from '@prisma/client';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';
import {
  toCustomerProfileDto, type ProfileDto,
} from './profiles.types.js';
import type { CustomerPatchBody, TechnicianPatchBody } from './profiles.schemas.js';
import { getTechnicianProfile, updateOwnTechnicianProfile } from '../technicians/technicians.service.js';

export interface AuthedUser { id: string; role: UserRole; }

export async function getMyProfile(user: AuthedUser): Promise<ProfileDto> {
  if (user.role === 'CUSTOMER') {
    const c = await prisma.customer.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!c) throw new NotFoundError('Profile not found');
    return toCustomerProfileDto(c);
  }
  if (user.role === 'TECHNICIAN') return getTechnicianProfile(user.id);
  throw new ForbiddenError('No self-service profile for this role');
}

export async function updateMyProfile(
  user: AuthedUser,
  patch: CustomerPatchBody | TechnicianPatchBody,
): Promise<ProfileDto> {
  if (user.role === 'CUSTOMER') {
    const fields = Object.keys(patch); // field NAMES only — never the values (no PII in audit)
    return prisma.$transaction(async (tx) => {
      const existing = await tx.customer.findFirst({ where: { userId: user.id, deletedAt: null } });
      if (!existing) throw new NotFoundError('Profile not found');
      const updated = await tx.customer.update({ where: { id: existing.id }, data: patch as CustomerPatchBody });
      await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: user.id, metadata: { fields } } });
      return toCustomerProfileDto(updated);
    });
  }
  if (user.role === 'TECHNICIAN') return updateOwnTechnicianProfile(user.id, patch as TechnicianPatchBody);
  throw new ForbiddenError('No self-service profile for this role');
}
