import type { Zone, ServiceCategory, Service, PartsCatalog } from '@prisma/client';

export interface ZoneDto { id: string; name: string; visitFeePaise: number; status: Zone['status']; }
export interface CategoryDto { id: string; name: string; status: ServiceCategory['status']; }
export interface ServicePriceDto {
  id: string;
  name: string;
  tier: Service['tier'];
  categoryId: string;
  laborPaise: number | null;   // null until a price is set for the requested zone
  visitFeePaise: number;       // the zone's visit fee
}

export function toZoneDto(z: Zone): ZoneDto {
  return { id: z.id, name: z.name, visitFeePaise: z.visitFeePaise, status: z.status };
}
export function toCategoryDto(c: ServiceCategory): CategoryDto {
  return { id: c.id, name: c.name, status: c.status };
}

export interface PartDto {
  id: string;
  sku: string;
  name: string;
  categoryId: string | null;
  ceilingPricePaise: number;
  status: PartsCatalog['status'];
}

export function toPartDto(p: PartsCatalog): PartDto {
  return { id: p.id, sku: p.sku, name: p.name, categoryId: p.categoryId, ceilingPricePaise: p.ceilingPricePaise, status: p.status };
}
