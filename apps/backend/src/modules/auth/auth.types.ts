import type { User, Admin } from '@prisma/client';

export interface UserDto {
  id: string;
  role: User['role'];
  status: User['status'];
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  user: UserDto;
}

export function toUserDto(user: User): UserDto {
  return { id: user.id, role: user.role, status: user.status };
}

export interface AdminDto {
  id: string;
  email: string;
  name: string;
  adminLevel: Admin['adminLevel'];
  status: Admin['status'];
}

/** Admin DTO — NEVER includes passwordHash. */
export function toAdminDto(admin: Admin): AdminDto {
  return { id: admin.id, email: admin.email, name: admin.name, adminLevel: admin.adminLevel, status: admin.status };
}

export interface AdminAuthTokens {
  accessToken: string;
  refreshToken: string;
  admin: AdminDto;
}
