import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';
import { resolvePincode } from './serviceability.service.js';
import { toAddressDto, type AddressDto } from './addresses.types.js';
import type { CreateAddressBody, UpdateAddressBody } from './addresses.schemas.js';

/** Resolve the caller's Customer row (CUSTOMER self-service only). */
async function requireCustomer(userId: string): Promise<{ id: string }> {
  const c = await prisma.customer.findFirst({ where: { userId, deletedAt: null } });
  if (!c) throw new ForbiddenError('Only customers have addresses');
  return { id: c.id };
}

/** Load an address scoped to the caller; 404 if not theirs or soft-deleted. */
async function ownAddressOrThrow(customerId: string, id: string) {
  const a = await prisma.address.findFirst({ where: { id, customerId, deletedAt: null } });
  if (!a) throw new NotFoundError('Address not found');
  return a;
}

export async function listAddresses(userId: string): Promise<AddressDto[]> {
  const { id: customerId } = await requireCustomer(userId);
  const rows = await prisma.address.findMany({
    where: { customerId, deletedAt: null, status: 'ACTIVE' },
    orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
  });
  return Promise.all(rows.map(async (a) => toAddressDto(a, await resolvePincode(a.pincode))));
}

export async function createAddress(userId: string, body: CreateAddressBody): Promise<AddressDto> {
  const { id: customerId } = await requireCustomer(userId);
  const svc = await resolvePincode(body.pincode);
  const row = await prisma.$transaction(async (tx) => {
    // status:'ACTIVE' to match listAddresses — the "first VISIBLE address auto-defaults" invariant
    const count = await tx.address.count({ where: { customerId, deletedAt: null, status: 'ACTIVE' } });
    const makeDefault = body.isDefault === true || count === 0;
    if (makeDefault) {
      await tx.address.updateMany({ where: { customerId, deletedAt: null, isDefault: true }, data: { isDefault: false } });
    }
    return tx.address.create({
      data: {
        customerId,
        label: body.label,
        line1: body.line1,
        line2: body.line2 ?? null,
        landmark: body.landmark ?? null,
        pincode: body.pincode,
        lat: body.lat ?? null,
        lng: body.lng ?? null,
        zoneId: svc.zone?.id ?? null,
        isDefault: makeDefault,
      },
    });
  });
  return toAddressDto(row, svc);
}

export async function getAddress(userId: string, id: string): Promise<AddressDto> {
  const { id: customerId } = await requireCustomer(userId);
  const a = await ownAddressOrThrow(customerId, id);
  return toAddressDto(a, await resolvePincode(a.pincode));
}

export async function updateAddress(userId: string, id: string, body: UpdateAddressBody): Promise<AddressDto> {
  const { id: customerId } = await requireCustomer(userId);
  await ownAddressOrThrow(customerId, id);
  const row = await prisma.$transaction(async (tx) => {
    const existing = await tx.address.findFirst({ where: { id, customerId, deletedAt: null } });
    if (!existing) throw new NotFoundError('Address not found');
    // Build the update payload field-by-field from the whitelisted body — never a blind spread,
    // so a future field added to UpdateAddressBody can't become a silent client-controlled write.
    const data: Prisma.AddressUpdateInput = {};
    if (body.label !== undefined) data.label = body.label;
    if (body.line1 !== undefined) data.line1 = body.line1;
    if (body.line2 !== undefined) data.line2 = body.line2;
    if (body.landmark !== undefined) data.landmark = body.landmark;
    if (body.lat !== undefined) data.lat = body.lat;
    if (body.lng !== undefined) data.lng = body.lng;
    if (body.isDefault !== undefined) data.isDefault = body.isDefault;
    if (body.pincode !== undefined) {
      data.pincode = body.pincode;
      const svc = await resolvePincode(body.pincode);
      data.zone = svc.zone ? { connect: { id: svc.zone.id } } : { disconnect: true };
    }
    if (body.isDefault === true) {
      await tx.address.updateMany({ where: { customerId, deletedAt: null, isDefault: true, NOT: { id } }, data: { isDefault: false } });
    }
    return tx.address.update({ where: { id }, data });
  });
  return toAddressDto(row, await resolvePincode(row.pincode));
}

export async function deleteAddress(userId: string, id: string): Promise<void> {
  const { id: customerId } = await requireCustomer(userId);
  await ownAddressOrThrow(customerId, id);
  // also clear isDefault so a soft-deleted row never lingers as a "default" (decision 7: no auto-promote)
  await prisma.address.update({ where: { id }, data: { deletedAt: new Date(), isDefault: false } });
}
