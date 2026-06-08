import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, UnprocessableError } from '../../shared/errors.js';
import { resolvePincode } from '../addresses/serviceability.service.js';
import { generateBookingNumber } from './bookings.number.js';
import { transitionBooking } from './bookings.state.js';
import { toBookingDto, type BookingDto } from './bookings.types.js';
import type { CreateBookingBody } from './bookings.schemas.js';

async function requireCustomer(userId: string): Promise<{ id: string }> {
  const c = await prisma.customer.findFirst({ where: { userId, deletedAt: null } });
  if (!c) throw new ForbiddenError('Only customers can book');
  return { id: c.id };
}

async function ownBookingOrThrow(customerId: string, id: string) {
  const b = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null } });
  if (!b) throw new NotFoundError('Booking not found');
  return b;
}

export async function createBooking(userId: string, body: CreateBookingBody): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);

  const address = await prisma.address.findFirst({ where: { id: body.addressId, customerId, deletedAt: null } });
  if (!address) throw new NotFoundError('Address not found');

  const service = await prisma.service.findFirst({ where: { id: body.serviceId, deletedAt: null, status: 'ACTIVE' } });
  if (!service) throw new NotFoundError('Service not found');

  const svc = await resolvePincode(address.pincode);
  if (!svc.serviceable || !svc.zone) throw new UnprocessableError("We don't serve this area yet");
  const zone = svc.zone;

  const price = await prisma.servicePrice.findUnique({
    where: { serviceId_zoneId: { serviceId: service.id, zoneId: zone.id } },
  });
  if (!price) throw new UnprocessableError('This service is unavailable in your area');

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const row = await prisma.$transaction(async (tx) => {
        const created = await tx.booking.create({
          data: {
            bookingNumber: generateBookingNumber(),
            customerId,
            addressId: address.id,
            serviceId: service.id,
            zoneId: zone.id,
            zoneName: zone.name,
            serviceName: service.name,
            visitFeePaise: zone.visitFeePaise,
            laborPaise: price.laborPaise,
            laborTier: service.tier,
            scheduledSlot: new Date(body.scheduledSlot),
          },
        });
        await tx.auditLog.create({
          data: { action: 'BOOKING_STATE_CHANGED', actorType: 'USER', actorId: userId,
                   metadata: { bookingId: created.id, from: null, to: 'CREATED' } },
        });
        return created;
      });
      return toBookingDto(row);
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') continue;
      throw e;
    }
  }
  throw new Error('Could not generate a unique booking number');
}

export async function listBookings(userId: string): Promise<BookingDto[]> {
  const { id: customerId } = await requireCustomer(userId);
  const rows = await prisma.booking.findMany({ where: { customerId, deletedAt: null }, orderBy: { createdAt: 'desc' } });
  return rows.map(toBookingDto);
}

export async function getBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const b = await ownBookingOrThrow(customerId, id);
  return toBookingDto(b);
}

export async function cancelBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await ownBookingOrThrow(customerId, id);
  const updated = await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'CANCELLED_BY_CUSTOMER', { type: 'USER', id: userId }),
  );
  return toBookingDto(updated);
}
