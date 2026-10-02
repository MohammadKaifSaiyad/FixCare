import type { Customer } from '@prisma/client';
import type { TechnicianProfileDto } from '../technicians/technicians.types.js';

export type { TechnicianProfileDto };

export interface CustomerProfileDto {
  id: string;
  role: 'CUSTOMER';
  name: string;
  status: Customer['status'];
}

export type ProfileDto = CustomerProfileDto | TechnicianProfileDto;

export function toCustomerProfileDto(c: Customer): CustomerProfileDto {
  return { id: c.id, role: 'CUSTOMER', name: c.name, status: c.status };
}
