import { prisma } from '../../shared/database/prisma.js';
import type { UserRole } from '@prisma/client';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';
import {
  toCustomerProfileDto, toTechnicianProfileDto, type ProfileDto,
} from './profiles.types.js';
import type { CustomerPatchBody, TechnicianPatchBody } from './profiles.schemas.js';

export interface AuthedUser { id: string; role: UserRole; }

export async function getMyProfile(user: AuthedUser): Promise<ProfileDto> {
  if (user.role === 'CUSTOMER') {
    const c = await prisma.customer.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!c) throw new NotFoundError('Profile not found');
    return toCustomerProfileDto(c);
  }
  if (user.role === 'TECHNICIAN') {
    const t = await prisma.technician.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!t) throw new NotFoundError('Profile not found');
    return toTechnicianProfileDto(t);
  }
  throw new ForbiddenError('No self-service profile for this role');
}

export async function updateMyProfile(
  user: AuthedUser,
  patch: CustomerPatchBody | TechnicianPatchBody,
): Promise<ProfileDto> {
  const fields = Object.keys(patch); // field NAMES only — never the values (no PII in audit)

  if (user.role === 'CUSTOMER') {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.customer.findFirst({ where: { userId: user.id, deletedAt: null } });
      if (!existing) throw new NotFoundError('Profile not found');
      const updated = await tx.customer.update({ where: { id: existing.id }, data: patch as CustomerPatchBody });
      await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: user.id, metadata: { fields } } });
      return toCustomerProfileDto(updated);
    });
  }
  if (user.role === 'TECHNICIAN') {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.technician.findFirst({ where: { userId: user.id, deletedAt: null } });
      if (!existing) throw new NotFoundError('Profile not found');
      const updated = await tx.technician.update({ where: { id: existing.id }, data: patch as TechnicianPatchBody });
      await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: user.id, metadata: { fields } } });
      return toTechnicianProfileDto(updated);
    });
  }
  throw new ForbiddenError('No self-service profile for this role');
}
