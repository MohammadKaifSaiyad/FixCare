import type { User } from '@prisma/client';

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
