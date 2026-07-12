import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, UnprocessableError, ConflictError, UnauthorizedError } from '../../shared/errors.js';
import { resolvePincode } from '../addresses/serviceability.service.js';
import { generateBookingNumber } from './bookings.number.js';
import { transitionBooking } from './bookings.state.js';
import { verifyArrivalCode } from './arrival-code.js';
import { haversineMeters } from '../../shared/utils/geo.js';
import { ARRIVAL_GEOFENCE_METERS } from './bookings.constants.js';
import { toBookingDto, toPhotoSummaries, type BookingDto } from './bookings.types.js';
import { sumParts } from './estimate.js';
import type { CreateBookingBody, ConfirmArrivalBody } from './bookings.schemas.js';

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

/** Owner-scoped load + DIAGNOSED guard shared by approve/decline — keeps the two money-gating
 *  transitions from drifting apart. 404 (not 403) on a foreign id (no IDOR); 409 if not awaiting a
 *  decision. */
async function ownDiagnosedBookingOrThrow(userId: string, id: string) {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await ownBookingOrThrow(customerId, id);
  if (booking.state !== 'DIAGNOSED') throw new ConflictError('Booking is not awaiting a decision');
  return booking;
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
        // auto-open to the technician pool (SYSTEM actor)
        const opened = await transitionBooking(tx, created, 'DISPATCHED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'system' });
        return opened;
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
  // include technician + cart so the list's estimate/diagnosis match the detail view (getBooking).
  const rows = await prisma.booking.findMany({
    where: { customerId, deletedAt: null },
    orderBy: { createdAt: 'desc' },
    include: { technician: { include: { user: true } }, bookingParts: true, photos: { where: { deletedAt: null } } },
  });
  return Promise.all(rows.map(async (b) =>
    toBookingDto(b, b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined, b.bookingParts, await toPhotoSummaries(b.photos)),
  ));
}

export async function getBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  // owner-scoped (another customer's id → 404, no IDOR); include the assigned technician (if any)
  const b = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { technician: { include: { user: true } }, bookingParts: true, photos: { where: { deletedAt: null } } },
  });
  if (!b) throw new NotFoundError('Booking not found');
  return toBookingDto(b, b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined, b.bookingParts, await toPhotoSummaries(b.photos));
}

export async function cancelBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await ownBookingOrThrow(customerId, id);
  const updated = await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'CANCELLED_BY_CUSTOMER', { type: 'USER', kind: 'CUSTOMER', id: userId }),
  );
  return toBookingDto(updated);
}

export async function confirmArrival(userId: string, id: string, body: ConfirmArrivalBody): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null }, include: { address: true } });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'EN_ROUTE') throw new ConflictError('Booking is not awaiting arrival confirmation');

  // Note: a correct code is consumed (single-use) by verifyArrivalCode BEFORE the $transaction below.
  // Redis and Postgres can't share a transaction; if the DB tx rolled back, the code would be spent
  // and the customer would need the technician to re-tap arrive. This fails SAFE (never a false
  // ARRIVED), and the DB tx here only sets timestamps/state — it does not realistically fail.
  const result = await verifyArrivalCode(id, body.code);
  if (result === 'no-code') {
    // Distinguish between "technician never tapped Arrived" vs "code was minted but exhausted/expired".
    // If GPS is recorded, the technician DID tap arrive (which always mints the code) — so 'no-code'
    // means the attempt cap was hit or the code expired → treat as invalid (401).
    const gpsPresent = booking.arrivalLat != null;
    if (gpsPresent) throw new UnauthorizedError('Invalid or expired arrival code');
    throw new ConflictError('The technician has not marked arrival yet');
  }
  if (result === 'invalid') throw new UnauthorizedError('Invalid or expired arrival code');

  // re-derive audit evidence from the persisted arrival GPS + the address (no raw coords in audit)
  const gpsRecorded = booking.arrivalLat != null && booking.arrivalLng != null;
  const withinGeofence =
    gpsRecorded && booking.address.lat != null && booking.address.lng != null
      ? haversineMeters(booking.address.lat, booking.address.lng, booking.arrivalLat!, booking.arrivalLng!) <= ARRIVAL_GEOFENCE_METERS
      : null;

  // Enforce (not just record) the geofence at confirm time: if the recorded arrival GPS is provably
  // outside the address geofence, the visit fee must not lock. (withinGeofence is null when the
  // address has no coords — record-only fallback, allowed.) Never grant ARRIVED while the audit says
  // the technician was not on-site.
  if (withinGeofence === false) throw new UnprocessableError('Arrival GPS is outside the service address');

  const updated = await prisma.$transaction(async (tx) => {
    await transitionBooking(
      tx, booking, 'ARRIVED', { type: 'USER', kind: 'CUSTOMER', id: userId },
      { gpsRecorded, withinGeofence, codeConfirmed: true },
    );
    return tx.booking.update({ where: { id }, data: { arrivedAt: new Date(), visitFeeLockedAt: new Date() } });
  });
  return toBookingDto(updated);
}

/** Customer approves the diagnosis → DIAGNOSED → CUSTOMER_APPROVED. Freezes the parts cart (further
 *  add/remove is rejected once the booking leaves DIAGNOSED). No money moves here — B6 handles charge. */
export async function approveDiagnosis(userId: string, id: string): Promise<BookingDto> {
  const booking = await ownDiagnosedBookingOrThrow(userId, id);
  const { updated, parts } = await prisma.$transaction(async (tx) => {
    // Read the cart inside the tx so the audit evidence reflects EXACTLY the cart frozen at approval
    // (the transition makes DIAGNOSED-only add/remove illegal, so the cart cannot change after this).
    const cart = await tx.bookingPart.findMany({ where: { bookingId: id } });
    const row = await transitionBooking(
      tx, booking, 'CUSTOMER_APPROVED', { type: 'USER', kind: 'CUSTOMER', id: userId },
      { source: 'customer_approval', partCount: cart.length, partsTotalPaise: sumParts(cart) },
    );
    return { updated: row, parts: cart };
  });
  return toBookingDto(updated, undefined, parts);
}

/** Customer declines the diagnosis → DIAGNOSED → DECLINED_BY_CUSTOMER (terminal). Records declinedAt.
 *  The visit fee stays locked (it locked at ARRIVED in B3) — declining does not refund the visit. */
export async function declineDiagnosis(userId: string, id: string): Promise<BookingDto> {
  const booking = await ownDiagnosedBookingOrThrow(userId, id);
  const { updated, parts } = await prisma.$transaction(async (tx) => {
    const cart = await tx.bookingPart.findMany({ where: { bookingId: id } });
    await transitionBooking(
      tx, booking, 'DECLINED_BY_CUSTOMER', { type: 'USER', kind: 'CUSTOMER', id: userId },
      { source: 'customer_decline', partCount: cart.length },
    );
    const row = await tx.booking.update({ where: { id }, data: { declinedAt: new Date() } });
    return { updated: row, parts: cart };
  });
  return toBookingDto(updated, undefined, parts);
}
