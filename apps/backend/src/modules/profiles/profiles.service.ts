import { prisma } from '../../shared/database/prisma.js';
import type { UserRole } from '@prisma/client';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';
import {
  toCustomerProfileDto, toTechnicianProfileDto, type ProfileDto,
} from './profiles.types.js';

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
