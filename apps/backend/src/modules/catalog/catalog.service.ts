import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ConflictError, NotFoundError } from '../../shared/errors.js';
import { toZoneDto, toCategoryDto, type ZoneDto, type CategoryDto } from './catalog.types.js';
import type { CreateZoneBody, UpdateZoneBody, CreateCategoryBody } from './catalog.schemas.js';

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
