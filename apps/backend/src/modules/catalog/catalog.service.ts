import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ConflictError, NotFoundError } from '../../shared/errors.js';
import { toZoneDto, toCategoryDto, type ZoneDto, type CategoryDto, type ServicePriceDto } from './catalog.types.js';
import type { CreateZoneBody, UpdateZoneBody, CreateCategoryBody, CreateServiceBody, UpsertPriceBody } from './catalog.schemas.js';

/** Map a Prisma unique-violation (P2002) to a 409. */
function asConflict(err: unknown, message: string): never {
  if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') throw new ConflictError(message);
  throw err;
}

export async function listZones(): Promise<ZoneDto[]> {
  const zones = await prisma.zone.findMany({ where: { deletedAt: null, status: 'ACTIVE' }, orderBy: { name: 'asc' } });
  return zones.map(toZoneDto);
}

export async function createZone(actorId: string, body: CreateZoneBody): Promise<ZoneDto> {
  try {
    return await prisma.$transaction(async (tx) => {
      const zone = await tx.zone.create({ data: { name: body.name, visitFeePaise: body.visitFeePaise } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'Zone', entityId: zone.id, fields: Object.keys(body) } } });
      return toZoneDto(zone);
    });
  } catch (e) { asConflict(e, 'A zone with that name already exists'); }
}

export async function updateZone(actorId: string, id: string, body: UpdateZoneBody): Promise<ZoneDto> {
  const existing = await prisma.zone.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Zone not found');
  return prisma.$transaction(async (tx) => {
    const zone = await tx.zone.update({ where: { id }, data: body });
    if (body.visitFeePaise !== undefined && body.visitFeePaise !== existing.visitFeePaise) {
      await tx.auditLog.create({ data: { action: 'PRICE_CHANGED', actorType: 'ADMIN', actorId, metadata: { entity: 'Zone', entityId: id, field: 'visitFeePaise', fromPaise: existing.visitFeePaise, toPaise: body.visitFeePaise } } });
    } else {
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'Zone', entityId: id, fields: Object.keys(body) } } });
    }
    return toZoneDto(zone);
  });
}

export async function listCategories(): Promise<CategoryDto[]> {
  const cats = await prisma.serviceCategory.findMany({ where: { deletedAt: null, status: 'ACTIVE' }, orderBy: { name: 'asc' } });
  return cats.map(toCategoryDto);
}

export async function createCategory(actorId: string, body: CreateCategoryBody): Promise<CategoryDto> {
  try {
    return await prisma.$transaction(async (tx) => {
      const cat = await tx.serviceCategory.create({ data: { name: body.name } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'ServiceCategory', entityId: cat.id, fields: Object.keys(body) } } });
      return toCategoryDto(cat);
    });
  } catch (e) { asConflict(e, 'A category with that name already exists'); }
}

export async function createService(actorId: string, body: CreateServiceBody) {
  const cat = await prisma.serviceCategory.findFirst({ where: { id: body.categoryId, deletedAt: null } });
  if (!cat) throw new NotFoundError('Category not found');
  try {
    return await prisma.$transaction(async (tx) => {
      const svc = await tx.service.create({ data: { categoryId: body.categoryId, name: body.name, tier: body.tier } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'Service', entityId: svc.id, fields: Object.keys(body) } } });
      return { id: svc.id, categoryId: svc.categoryId, name: svc.name, tier: svc.tier, status: svc.status };
    });
  } catch (e) { asConflict(e, 'A service with that name already exists in this category'); }
}

/** Active services for a zone: each carries its laborPaise for that zone (null if unpriced) + the zone visit fee. */
export async function listServicesByZone(zoneId: string, categoryId?: string): Promise<ServicePriceDto[]> {
  const zone = await prisma.zone.findFirst({ where: { id: zoneId, deletedAt: null } });
  if (!zone) throw new NotFoundError('Zone not found');
  const services = await prisma.service.findMany({
    where: { deletedAt: null, status: 'ACTIVE', ...(categoryId ? { categoryId } : {}) },
    include: { prices: { where: { zoneId } } },
    orderBy: { name: 'asc' },
  });
  return services.map((s) => ({
    id: s.id, name: s.name, tier: s.tier, categoryId: s.categoryId,
    laborPaise: s.prices[0]?.laborPaise ?? null,
    visitFeePaise: zone.visitFeePaise,
  }));
}

export async function upsertServicePrice(actorId: string, serviceId: string, zoneId: string, body: UpsertPriceBody) {
  const svc = await prisma.service.findFirst({ where: { id: serviceId, deletedAt: null } });
  if (!svc) throw new NotFoundError('Service not found');
  const zone = await prisma.zone.findFirst({ where: { id: zoneId, deletedAt: null } });
  if (!zone) throw new NotFoundError('Zone not found');
  return prisma.$transaction(async (tx) => {
    const existing = await tx.servicePrice.findUnique({ where: { serviceId_zoneId: { serviceId, zoneId } } });
    const row = await tx.servicePrice.upsert({
      where: { serviceId_zoneId: { serviceId, zoneId } },
      create: { serviceId, zoneId, laborPaise: body.laborPaise },
      update: { laborPaise: body.laborPaise },
    });
    await tx.auditLog.create({ data: { action: 'PRICE_CHANGED', actorType: 'ADMIN', actorId, metadata: { entity: 'ServicePrice', entityId: row.id, zoneId, field: 'laborPaise', fromPaise: existing?.laborPaise ?? null, toPaise: body.laborPaise } } });
    return { id: row.id, serviceId, zoneId, laborPaise: row.laborPaise };
  });
}
