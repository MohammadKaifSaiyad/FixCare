import { Prisma, type PaymentStatus, type PaymentMethod } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, UnprocessableError, ConflictError, UnauthorizedError, TooManyRequestsError } from '../../shared/errors.js';
import { resolvePincode } from '../addresses/serviceability.service.js';
import { generateBookingNumber } from './bookings.number.js';
import { transitionBooking } from './bookings.state.js';
import { verifyArrivalCode } from './arrival-code.js';
import { mintCompletionCode } from './completion-code.js';
import { mintCashReceiptCode, cashCollectedLast24hPaise } from './cash.js';
import { haversineMeters } from '../../shared/utils/geo.js';
import { ARRIVAL_GEOFENCE_METERS } from './bookings.constants.js';
import { toBookingDto, toPhotoSummaries, type BookingDto, type PaymentSummary } from './bookings.types.js';
import { sumParts } from './estimate.js';
import { chargeAmountFor } from './charge.js';
import { paymentGateway } from '../../shared/third-party/razorpay.js';
import type { CreateBookingBody, ConfirmArrivalBody } from './bookings.schemas.js';
import { config } from '../../shared/config.js';
import { makeOtpSender } from '../../shared/third-party/otp-sender.js';

const otpSender = makeOtpSender();

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

/** Pick the payment the customer should see: the CAPTURED one if any, else the latest attempt.
 *  take-1-latest alone is WRONG since B6b: a stale CASH CREATED attempt (created after the UPI
 *  order) would mask a UPI capture — a PAID booking showing a pending payment. Attempts per
 *  booking are bounded tiny, so fetching all and picking here is cheap. */
function pickPaymentSummary(payments: { status: PaymentStatus; method: PaymentMethod; amountPaise: number }[]): PaymentSummary | null {
  const p = payments.find((x) => x.status === 'CAPTURED') ?? payments[0];
  return p ? { status: p.status, method: p.method, amountPaise: p.amountPaise } : null;
}

export async function listBookings(userId: string): Promise<BookingDto[]> {
  const { id: customerId } = await requireCustomer(userId);
  // include technician + cart so the list's estimate/diagnosis match the detail view (getBooking).
  const rows = await prisma.booking.findMany({
    where: { customerId, deletedAt: null },
    orderBy: { createdAt: 'desc' },
    include: { technician: { include: { user: true } }, bookingParts: true, photos: { where: { deletedAt: null } }, payments: { orderBy: { createdAt: 'desc' } } },
  });
  return Promise.all(rows.map(async (b) =>
    toBookingDto(
      b,
      b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined,
      b.bookingParts,
      await toPhotoSummaries(b.photos),
      pickPaymentSummary(b.payments),
    ),
  ));
}

export async function getBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  // owner-scoped (another customer's id → 404, no IDOR); include the assigned technician (if any)
  const b = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { technician: { include: { user: true } }, bookingParts: true, photos: { where: { deletedAt: null } }, payments: { orderBy: { createdAt: 'desc' } } },
  });
  if (!b) throw new NotFoundError('Booking not found');
  return toBookingDto(
    b,
    b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined,
    b.bookingParts,
    await toPhotoSummaries(b.photos),
    pickPaymentSummary(b.payments),
  );
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

/** Customer taps "confirm work completed" → mint the completion code and send it to THEIR phone.
 *  The technician can only close the job by hearing this code from the customer (Rule 2). */
export async function requestCompletionOtp(userId: string, id: string): Promise<{ ok: true; devOtp?: string }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { customer: { include: { user: true } } },
  });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'REPAIR_COMPLETE') throw new ConflictError('Booking is not awaiting completion confirmation');
  const r = await mintCompletionCode(id);
  if (r.status === 'throttled') throw new TooManyRequestsError('Too many code requests. Try again later.');
  await otpSender.send(booking.customer.user.phone, r.code);
  return config.NODE_ENV === 'production' ? { ok: true } : { ok: true, devOtp: r.code };
}

/** Customer initiates the UPI charge. Idempotent: an open (CREATED) attempt returns the SAME
 *  order — double-taps and app restarts never create duplicate gateway orders. */
export async function initiatePayment(userId: string, id: string): Promise<{ orderId: string; amountPaise: number; keyId: string | null }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { bookingParts: true },
  });
  if (!booking) throw new NotFoundError('Booking not found');

  // Existing-attempt guards FIRST: once the booking is paid (either method), chargeAmountFor
  // would 409 with the wrong story ("not awaiting payment") — a stale retry must hear "already
  // paid". CAPTURED is method-agnostic: a cash-paid booking rejects /pay the same way.
  const captured = await prisma.payment.findFirst({ where: { bookingId: id, status: 'CAPTURED' } });
  if (captured) throw new ConflictError('This booking is already paid');
  const existing = await prisma.payment.findFirst({ where: { bookingId: id, method: 'UPI', status: 'CREATED' }, orderBy: { createdAt: 'desc' } });
  if (existing?.razorpayOrderId) {
    return { orderId: existing.razorpayOrderId, amountPaise: existing.amountPaise, keyId: config.RAZORPAY_KEY_ID ?? null };
  }

  const amountPaise = chargeAmountFor(booking, booking.bookingParts); // 409s on non-payable states
  if (amountPaise === 0) {
    // Nothing is owed (visit-fee credit covered the whole job). Razorpay rejects sub-₹1 orders,
    // and a 0-amount Payment row would let a 0-amount capture "pay" the booking. Zero-payable
    // settlement (auto-close without a charge) belongs to B6c with the CLOSED wiring.
    throw new UnprocessableError('Nothing is payable for this booking');
  }

  // Gateway order BEFORE the tx: an orphaned order from a tx failure is harmless (unpaid orders
  // expire gateway-side); a DB row without an order would be a broken checkout.
  const { orderId } = await paymentGateway.createOrder(amountPaise, id);
  await prisma.$transaction(async (tx) => {
    await tx.payment.create({ data: { bookingId: id, method: 'UPI', amountPaise, razorpayOrderId: orderId } });
    await tx.auditLog.create({
      data: { action: 'PAYMENT_EVENT', actorType: 'USER', actorId: userId, metadata: { bookingId: id, event: 'order_created', amountPaise } },
    });
  });
  return { orderId, amountPaise, keyId: config.RAZORPAY_KEY_ID ?? null };
}

/** Customer confirms "I will pay ₹X cash" → gates checked → CASH attempt + receipt OTP minted to
 *  THEIR phone. The technician can only capture by hearing this code from the customer (Rule 2).
 *  Idempotent on the attempt row; each call re-mints (send-throttled 3/900s). */
export async function initiateCashPayment(userId: string, id: string): Promise<{ amountPaise: number; devOtp?: string }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { bookingParts: true, customer: { include: { user: true } } },
  });
  if (!booking) throw new NotFoundError('Booking not found');

  const captured = await prisma.payment.findFirst({ where: { bookingId: id, status: 'CAPTURED' } });
  if (captured) throw new ConflictError('This booking is already paid');

  const amountPaise = chargeAmountFor(booking, booking.bookingParts); // 409s on non-payable states
  if (amountPaise === 0) throw new UnprocessableError('Nothing is payable for this booking');
  if (!booking.technicianId) throw new ConflictError('Booking is not awaiting payment'); // unreachable in payable states; narrows the type

  // Mirror confirm-cash's requireTechnician filters (deletedAt + VERIFIED): if the assigned
  // technician can no longer capture, initiating would mint an OTP that can NEVER be entered —
  // a dead-end the customer can't diagnose. Fail here with the UPI fallback instead.
  const tech = await prisma.technician.findFirst({
    where: { id: booking.technicianId, deletedAt: null, status: 'VERIFIED' },
    select: { cashDebtPaise: true },
  });
  if (!tech) throw new UnprocessableError('Cash is unavailable for this booking — please pay by UPI');

  // UX-level gate checks — the ENFORCEMENT re-runs inside the capture tx post-lock (Task 3).
  if (tech.cashDebtPaise + amountPaise > config.CASH_DEBT_LIMIT_PAISE) {
    throw new UnprocessableError('Cash limit reached for this technician — please pay by UPI');
  }
  if ((await cashCollectedLast24hPaise(prisma, booking.technicianId)) + amountPaise > config.CASH_VELOCITY_CAP_PAISE) {
    throw new UnprocessableError('Cash limit reached for this technician — please pay by UPI');
  }

  // Reuse the open CASH attempt (idempotent like /pay — double-taps never duplicate rows).
  const payment = await prisma.$transaction(async (tx) => {
    const open = await tx.payment.findFirst({ where: { bookingId: id, method: 'CASH', status: 'CREATED' } });
    // Reuse is deliberate on BOTH counts: no second cash_initiated audit (a re-mint is a UX retry,
    // not a new financial act — one attempt, one event) and the OTP payload below re-pins the
    // EXISTING row's amount, not the recomputed one. Both amounts are identical while payable
    // states freeze the total; if a future slice lets the payable change post-initiation, the open
    // attempt must be superseded (FAILED + new row), not reused.
    if (open) return open;
    const row = await tx.payment.create({ data: { bookingId: id, method: 'CASH', amountPaise } });
    await tx.auditLog.create({
      data: { action: 'PAYMENT_EVENT', actorType: 'USER', actorId: userId, metadata: { bookingId: id, event: 'cash_initiated', amountPaise } },
    });
    return row;
  });

  const r = await mintCashReceiptCode(id, { paymentId: payment.id, amountPaise: payment.amountPaise });
  if (r.status === 'throttled') throw new TooManyRequestsError('Too many code requests. Try again later.');
  await otpSender.send(booking.customer.user.phone, r.code);
  return config.NODE_ENV === 'production'
    ? { amountPaise: payment.amountPaise }
    : { amountPaise: payment.amountPaise, devOtp: r.code };
}
