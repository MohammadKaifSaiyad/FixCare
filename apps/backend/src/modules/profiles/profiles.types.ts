import type { Customer, Technician } from '@prisma/client';

export interface CustomerProfileDto {
  id: string;
  role: 'CUSTOMER';
  name: string;
  status: Customer['status'];
}

export interface TechnicianProfileDto {
  id: string;
  role: 'TECHNICIAN';
  name: string;
  skills: Technician['skills'];
  status: Technician['status'];
}

export type ProfileDto = CustomerProfileDto | TechnicianProfileDto;

export function toCustomerProfileDto(c: Customer): CustomerProfileDto {
  return { id: c.id, role: 'CUSTOMER', name: c.name, status: c.status };
}

export function toTechnicianProfileDto(t: Technician): TechnicianProfileDto {
  return { id: t.id, role: 'TECHNICIAN', name: t.name, skills: t.skills, status: t.status };
}
