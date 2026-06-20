import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, ConflictError, UnprocessableError } from '../../shared/errors.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import { haversineMeters } from '../../shared/utils/geo.js';
import { mintArrivalCode } from '../bookings/arrival-code.js';
import { ARRIVAL_GEOFENCE_METERS } from '../bookings/bookings.constants.js';
import { toTechnicianJobDto, type TechnicianJobDto } from './technician-jobs.types.js';
import type { ArriveBody, DiagnoseBody, AddPartBody } from './technician-jobs.schemas.js';

async function requireTechnician(userId: string): Promise<{ id: string; skills: import('@prisma/client').ServiceSkill[] }> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!t || t.status !== 'VERIFIED') throw new ForbiddenError('Verified technician required');
  return { id: t.id, skills: t.skills };
}

export async function listAvailableJobs(userId: string): Promise<TechnicianJobDto[]> {
  const tech = await requireTechnician(userId);
  const skipped = await prisma.jobSkip.findMany({ where: { technicianId: tech.id }, select: { bookingId: true } });
  const skippedIds = skipped.map((s) => s.bookingId);
  const bookings = await prisma.booking.findMany({
    where: {
      state: 'DISPATCHED',
      technicianId: null,
      deletedAt: null,
      id: { notIn: skippedIds.length ? skippedIds : undefined },
      service: { requiredSkill: { in: tech.skills } },
    },
    include: { address: true, service: true, customer: { include: { user: true } } },
    orderBy: { createdAt: 'desc' },
  });
  return bookings.map((b) => toTechnicianJobDto(b, b.address, b.service.requiredSkill, b.customer.user.phone));
}

export async function listMyJobs(userId: string): Promise<TechnicianJobDto[]> {
  const tech = await requireTechnician(userId);
  const bookings = await prisma.booking.findMany({
    where: { technicianId: tech.id, deletedAt: null },
    include: { address: true, service: true, customer: { include: { user: true } } },
    orderBy: { createdAt: 'desc' },
  });
  return bookings.map((b) => toTechnicianJobDto(b, b.address, b.service.requiredSkill, b.customer.user.phone));
}

export async function acceptJob(userId: string, bookingId: string): Promise<TechnicianJobDto> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { service: true } });
  if (!booking) throw new NotFoundError('Job not found');
  if (booking.state !== 'DISPATCHED' || booking.technicianId) throw new ConflictError('This job is no longer available');
  if (!tech.skills.includes(booking.service.requiredSkill)) throw new ForbiddenError('You are not skilled for this job');

  await prisma.$transaction(async (tx) => {
    // transitionBooking does the optimistic-locked DISPATCHED→ACCEPTED + audit; concurrent loser gets count===0 → ConflictError (409)
    await transitionBooking(tx, booking, 'ACCEPTED', { type: 'USER', kind: 'TECHNICIAN', id: userId });
    // Claim defense-in-depth: only set technicianId if still unclaimed. The state lock above already
    // serializes accepts, but guarding technicianId here keeps the claim provably single even if the
    // ordering is ever changed — a booking must never end with two technicians.
    const claim = await tx.booking.updateMany({ where: { id: bookingId, technicianId: null }, data: { technicianId: tech.id } });
    if (claim.count === 0) throw new ConflictError('This job is no longer available');
  });
  const full = await prisma.booking.findFirstOrThrow({
    where: { id: bookingId, deletedAt: null },
    include: { address: true, service: true, customer: { include: { user: true } } },
  });
  return toTechnicianJobDto(full, full.address, full.service.requiredSkill, full.customer.user.phone);
}

export async function skipJob(userId: string, bookingId: string): Promise<void> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Job not found');
  await prisma.jobSkip.upsert({
    where: { technicianId_bookingId: { technicianId: tech.id, bookingId } },
    create: { technicianId: tech.id, bookingId },
    update: {},
  });
}



/** Load a booking that must be assigned to this technician + in the given state. */
async function ownAssignedBookingOrThrow(techId: string, bookingId: string, expectedState: 'ACCEPTED' | 'EN_ROUTE' | 'DIAGNOSED') {
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { address: true, service: true } });
  if (!b) throw new NotFoundError('Job not found');
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you');
  if (b.state !== expectedState) throw new ConflictError(`Job is not in ${expectedState}`);
  return b;
}

/** ACCEPTED → EN_ROUTE ("on my way"). Returns a minimal status object the technician app needs. */
export async function enRouteJob(userId: string, bookingId: string): Promise<{ id: string; state: 'EN_ROUTE' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'ACCEPTED');
  await prisma.$transaction((tx) => transitionBooking(tx, booking, 'EN_ROUTE', { type: 'USER', kind: 'TECHNICIAN', id: userId }));
  return { id: bookingId, state: 'EN_ROUTE' };
}

/** Arrive-tap: GPS gate (validate-if-present) + record GPS + mint the single-use code. NO state change. */
export async function arriveJob(userId: string, bookingId: string, body: ArriveBody): Promise<{ arrivalCode: string; withinGeofence: boolean | null }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'EN_ROUTE');

  // Record the technician's claimed GPS FIRST — fraud-defense #11 wants the GPS of every arrive-tap
  // captured for later review, INCLUDING a rejected too-far attempt (a technician probing the
  // geofence from 500m must leave a trace, not silently retry from closer).
  await prisma.booking.update({ where: { id: bookingId }, data: { arrivalLat: body.lat, arrivalLng: body.lng } });

  let withinGeofence: boolean | null = null;
  if (booking.address.lat != null && booking.address.lng != null) {
    const dist = haversineMeters(booking.address.lat, booking.address.lng, body.lat, body.lng);
    if (dist > ARRIVAL_GEOFENCE_METERS) throw new UnprocessableError('You are too far from the customer location');
    withinGeofence = true;
  }
  const arrivalCode = await mintArrivalCode(bookingId);
  return { arrivalCode, withinGeofence };
}

export async function diagnoseJob(userId: string, bookingId: string, body: DiagnoseBody): Promise<{ id: string; state: 'DIAGNOSED' }> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { service: true } });
  if (!booking) throw new NotFoundError('Job not found');
  if (booking.technicianId !== tech.id) throw new ForbiddenError('This job is not assigned to you');
  if (booking.state !== 'ARRIVED') throw new ConflictError('Job is not in ARRIVED');
  const issue = await prisma.diagnosedIssue.findFirst({ where: { id: body.diagnosedIssueId, deletedAt: null, status: 'ACTIVE' } });
  if (!issue) throw new NotFoundError('Diagnosed issue not found');
  if (issue.categoryId !== booking.service.categoryId) throw new UnprocessableError('That issue does not apply to this service');

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: { diagnosedIssueId: issue.id, diagnosedIssueName: issue.name, diagnosedAt: new Date() } });
    // transitionBooking checks the from-state (still ARRIVED in this tx) via its optimistic lock.
    await transitionBooking(tx, booking, 'DIAGNOSED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { diagnosedIssueId: issue.id });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'diagnosed', diagnosedIssueId: issue.id } } });
  });
  return { id: bookingId, state: 'DIAGNOSED' };
}

export async function addPart(userId: string, bookingId: string, body: AddPartBody): Promise<{ id: string }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'DIAGNOSED');
  const cat = await prisma.partsCatalog.findFirst({ where: { id: body.partsCatalogId, deletedAt: null, status: 'ACTIVE' } });
  if (!cat) throw new NotFoundError('Part not found');
  // A category-scoped part must match the booking's service category (no padding the cart with
  // unrelated parts to inflate the estimate). A null categoryId is a generic part — allowed anywhere.
  if (cat.categoryId !== null && cat.categoryId !== booking.service.categoryId) {
    throw new UnprocessableError('This part does not apply to this service category');
  }
  const line = await prisma.$transaction(async (tx) => {
    // Re-assert DIAGNOSED inside the tx (optimistic guard, same idiom as transitionBooking): if the
    // customer approved/declined concurrently the cart is frozen, so this matches 0 rows → reject.
    await assertStillDiagnosed(tx, bookingId);
    const created = await tx.bookingPart.create({
      data: { bookingId, partsCatalogId: cat.id, sku: cat.sku, name: cat.name, ceilingPricePaise: cat.ceilingPricePaise, qty: body.qty },
    });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'part_added', sku: cat.sku, qty: body.qty } } });
    return created;
  });
  return { id: line.id };
}

/** Optimistic freeze guard: a no-op update conditional on the booking still being DIAGNOSED. 0 rows
 *  affected means a concurrent approve/decline already left DIAGNOSED → the cart is frozen. */
async function assertStillDiagnosed(tx: import('@prisma/client').Prisma.TransactionClient, bookingId: string): Promise<void> {
  const r = await tx.booking.updateMany({ where: { id: bookingId, state: 'DIAGNOSED' }, data: { updatedAt: new Date() } });
  if (r.count === 0) throw new ConflictError('The cart is frozen — the booking is no longer in DIAGNOSED');
}

export async function removePart(userId: string, bookingId: string, partId: string): Promise<void> {
  const tech = await requireTechnician(userId);
  await ownAssignedBookingOrThrow(tech.id, bookingId, 'DIAGNOSED');
  const line = await prisma.bookingPart.findFirst({ where: { id: partId, bookingId } });
  if (!line) throw new NotFoundError('Part line not found');
  await prisma.$transaction(async (tx) => {
    await assertStillDiagnosed(tx, bookingId);
    // deleteMany (scoped to {id, bookingId}) is idempotent — a concurrent double-remove deletes 0 rows
    // instead of throwing Prisma P2025; the findFirst above already established the 404 case.
    await tx.bookingPart.deleteMany({ where: { id: partId, bookingId } });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'part_removed', sku: line.sku } } });
  });
}
