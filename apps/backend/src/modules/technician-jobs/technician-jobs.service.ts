import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, ConflictError, UnprocessableError, UnauthorizedError } from '../../shared/errors.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import { verifyCompletionCode } from '../bookings/completion-code.js';
import { haversineMeters } from '../../shared/utils/geo.js';
import { mintArrivalCode } from '../bookings/arrival-code.js';
import { ARRIVAL_GEOFENCE_METERS } from '../bookings/bookings.constants.js';
import { toTechnicianJobDto, toTechnicianJobDetailDto, type TechnicianJobDto, type TechnicianJobDetailDto } from './technician-jobs.types.js';
import { toPhotoSummaries } from '../bookings/bookings.types.js';
import { photoStorage } from '../../shared/third-party/r2-storage.js';
import { randomUUID } from 'node:crypto';
import { DIAGNOSIS_KINDS, REPAIR_KINDS, PHOTO_WINDOW, photoKind, type PhotoKindValue, type ArriveBody, type DiagnoseBody, type AddPartBody, type SignPhotoBody, type ConfirmPhotoBody, type ConfirmCompletionBody, type ConfirmCashBody } from './technician-jobs.schemas.js';
import { verifyCashReceiptCode, cashCollectedLast24hPaise } from '../bookings/cash.js';
import { config } from '../../shared/config.js';
import { recordCashCollected } from '../settlements/settlements.service.js';
import { computeEstimate, sumParts } from '../bookings/estimate.js';
import { technicianZoneIds } from '../technicians/technicians.service.js';

/** Stable machine codes for "this job is gone / not yours" — the technician app's job-detail screen keys its
 *  "no longer available" exit on these (never on the human message). */
const JOB_NOT_FOUND = 'JOB_NOT_FOUND';
const JOB_NOT_ASSIGNED = 'JOB_NOT_ASSIGNED';
/** The cart moved under the technician's confirm dialog (a line added/removed elsewhere) — re-review and resend. */
const ESTIMATE_CHANGED = 'ESTIMATE_CHANGED';
const ESTIMATE_CHANGED_MESSAGE = 'The estimate changed — check the parts and send again';

const TECHNICIAN_NOT_VERIFIED = 'TECHNICIAN_NOT_VERIFIED';
const JOB_OUT_OF_ZONE = 'JOB_OUT_OF_ZONE';

async function requireTechnician(userId: string): Promise<{ id: string; skills: import('@prisma/client').ServiceSkill[]; zoneIds: string[] }> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  // Stable code: the technician app re-checks the profile on it (suspended mid-session → Suspended screen).
  if (!t || t.status !== 'VERIFIED') throw new ForbiddenError('Verified technician required', TECHNICIAN_NOT_VERIFIED);
  return { id: t.id, skills: t.skills, zoneIds: await technicianZoneIds(t.id) };
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
      zoneId: { in: tech.zoneIds }, // the booking's SNAPSHOTTED zone — never re-resolved from the address
    },
    include: { address: true, service: true, customer: { include: { user: true } } },
    orderBy: { createdAt: 'desc' },
  });
  return bookings.map((b) => toTechnicianJobDto(b, b.address, b.service, b.customer.user.phone));
}

export async function listMyJobs(userId: string): Promise<TechnicianJobDto[]> {
  const tech = await requireTechnician(userId);
  const bookings = await prisma.booking.findMany({
    where: { technicianId: tech.id, deletedAt: null },
    include: { address: true, service: true, customer: { include: { user: true } }, photos: { where: { deletedAt: null } } },
    orderBy: { createdAt: 'desc' },
  });
  return Promise.all(bookings.map(async (b) => toTechnicianJobDto(b, b.address, b.service, b.customer.user.phone, await toPhotoSummaries(b.photos))));
}

/** One job, in full, for its assigned technician — the job-detail screen's poll target (one booking + its
 *  cart + its photos, instead of the whole history). Any state is readable while assigned. */
export async function getMyJob(userId: string, bookingId: string): Promise<TechnicianJobDetailDto> {
  const tech = await requireTechnician(userId);
  const b = await prisma.booking.findFirst({
    where: { id: bookingId, deletedAt: null },
    include: {
      address: true,
      service: true,
      customer: { include: { user: true } },
      photos: { where: { deletedAt: null } },
      bookingParts: { orderBy: { createdAt: 'asc' } },
    },
  });
  if (!b) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  if (b.technicianId !== tech.id) throw new ForbiddenError('This job is not assigned to you', JOB_NOT_ASSIGNED);
  return toTechnicianJobDetailDto(b, b.address, b.service, b.customer.user.phone, await toPhotoSummaries(b.photos), b.bookingParts);
}

export async function acceptJob(userId: string, bookingId: string): Promise<TechnicianJobDto> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { service: true } });
  if (!booking) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  if (booking.state !== 'DISPATCHED' || booking.technicianId) throw new ConflictError('This job is no longer available');
  if (!tech.skills.includes(booking.service.requiredSkill)) throw new ForbiddenError('You are not skilled for this job');
  if (!tech.zoneIds.includes(booking.zoneId)) throw new ForbiddenError('This job is outside your service zones', JOB_OUT_OF_ZONE);
  // B6c accept-gate (core-flow: "technician at cash debt limit → cannot accept"). Deferred from
  // B6b until settlement existed — auto-offset now gives a self-healing path out of the lockout.
  // Note: requireTechnician returns {id, skills, zoneIds} (no cash debt), so cashDebtPaise is fetched separately here.
  // Pre-tx check, UX friction ONLY — a concurrent settlement could flip this between the read and
  // the accept tx. Deliberately NOT a financial invariant (no money moves in accept).
  const techRow = await prisma.technician.findUniqueOrThrow({ where: { id: tech.id }, select: { cashDebtPaise: true } });
  // `>` not `>=`: the cash gates (initiate + capture) both ALLOW debt to land at EXACTLY the limit,
  // so accept must too — otherwise one legitimate capture to exactly the limit locks the technician
  // out of the next job the platform's own capture gate said they could take.
  if (techRow.cashDebtPaise > config.CASH_DEBT_LIMIT_PAISE) {
    throw new UnprocessableError('Settle your cash debt to accept new jobs');
  }

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
  return toTechnicianJobDto(full, full.address, full.service, full.customer.user.phone);
}

export async function skipJob(userId: string, bookingId: string): Promise<void> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  await prisma.jobSkip.upsert({
    where: { technicianId_bookingId: { technicianId: tech.id, bookingId } },
    create: { technicianId: tech.id, bookingId },
    update: {},
  });
}



/** Load a booking that must be assigned to this technician + in one of the given state(s). */
async function ownAssignedBookingOrThrow(
  techId: string,
  bookingId: string,
  expectedState: import('@prisma/client').BookingState | readonly import('@prisma/client').BookingState[],
) {
  const states = Array.isArray(expectedState) ? expectedState : [expectedState];
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { address: true, service: true } });
  if (!b) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you', JOB_NOT_ASSIGNED);
  if (!states.includes(b.state)) throw new ConflictError(`Job is not in ${states.join(' or ')}`);
  return b;
}

/** The cart is editable only while the technician is diagnosing (ARRIVED). "Submit diagnosis" sends the
 *  complete estimate and freezes it, so the customer can only ever approve a final cart (no instant
 *  labor-only approval, no bait-and-switch). */
export const CART_LOCKED_MESSAGE = 'The cart is locked — the diagnosis has been submitted';
const DUPLICATE_PART_MESSAGE = 'This part is already in the estimate — remove it to change the quantity';
/** Upper bound on lines in one estimate (each line's qty is separately capped at 99 by the schema). */
const MAX_CART_LINES = 20;

/** Own + assigned + cart open. After diagnose (`diagnosedAt` set) the message says the cart is locked;
 *  before arrival it is the usual wrong-state 409. */
async function ownOpenCartBookingOrThrow(techId: string, bookingId: string) {
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { address: true, service: true } });
  if (!b) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you', JOB_NOT_ASSIGNED);
  if (b.state !== 'ARRIVED') throw new ConflictError(b.diagnosedAt ? CART_LOCKED_MESSAGE : 'Job is not in ARRIVED');
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
  if (!booking) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  if (booking.technicianId !== tech.id) throw new ForbiddenError('This job is not assigned to you', JOB_NOT_ASSIGNED);
  if (booking.state !== 'ARRIVED') throw new ConflictError('Job is not in ARRIVED');
  const issue = await prisma.diagnosedIssue.findFirst({ where: { id: body.diagnosedIssueId, deletedAt: null, status: 'ACTIVE' } });
  if (!issue) throw new NotFoundError('Diagnosed issue not found');
  if (issue.categoryId !== booking.service.categoryId) throw new UnprocessableError('That issue does not apply to this service');

  await prisma.$transaction(async (tx) => {
    // Take the booking row lock FIRST (this update blocks concurrent confirmPhoto txs, which also
    // write the booking row via assertStillInState) so the photo read below sees the FINAL committed
    // slot set — otherwise a retake could commit between our read and our commit, and the audit's
    // photoIds would reference a soft-deleted row instead of its active replacement.
    await tx.booking.update({ where: { id: bookingId }, data: { diagnosedIssueId: issue.id, diagnosedIssueName: issue.name, diagnosedAt: new Date() } });
    // Photo gate (B4b): both diagnosis slots must have an ACTIVE photo before the booking can be
    // DIAGNOSED — the photos are the evidence behind the estimate the customer approves (Rule 1).
    const activePhotos = await tx.photoEvidence.findMany({
      where: { bookingId, deletedAt: null, kind: { in: [...DIAGNOSIS_KINDS] } },
      select: { id: true, kind: true },
    });
    const slots = new Set(activePhotos.map((p) => p.kind));
    if (!DIAGNOSIS_KINDS.every((k) => slots.has(k))) {
      throw new UnprocessableError('2 diagnosis photos required (overview + close-up)');
    }
    // The cart IS the estimate the customer will approve — snapshot exactly what was sent. Read after the
    // booking-row lock above: a part add that committed first is included; one racing this tx is rejected
    // by assertCartStillOpen once the state leaves ARRIVED.
    // Per-line evidence (not just count + total): the exact cart the customer will see can be
    // reconstructed from the audit log alone, even though removed lines are hard-deleted.
    const cartRows = await tx.bookingPart.findMany({ where: { bookingId }, orderBy: { createdAt: 'asc' }, select: { id: true, sku: true, name: true, qty: true, ceilingPricePaise: true } });
    // Bind to the cart the technician confirmed: the dialog's snapshot must be EXACTLY the frozen set (read
    // after the row lock), otherwise the customer would be sent an estimate the technician never reviewed.
    // Throwing rolls the whole tx back — the booking stays ARRIVED and nothing is written.
    if (body.expectedPartLineIds !== undefined && !sameIdSet(body.expectedPartLineIds, cartRows.map((l) => l.id))) {
      throw new ConflictError(ESTIMATE_CHANGED_MESSAGE, ESTIMATE_CHANGED);
    }
    const cart = cartRows.map(({ sku, name, qty, ceilingPricePaise }) => ({ sku, name, qty, ceilingPricePaise }));
    // transitionBooking checks the from-state (still ARRIVED in this tx) via its optimistic lock.
    await transitionBooking(tx, booking, 'DIAGNOSED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { diagnosedIssueId: issue.id, photoIds: activePhotos.map((p) => p.id), partCount: cart.length, partsTotalPaise: sumParts(cart), lines: cart });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'diagnosed', diagnosedIssueId: issue.id } } });
  });
  return { id: bookingId, state: 'DIAGNOSED' };
}

/** Set equality of two id lists (order-insensitive; a duplicate in `expected` can never match a cart of unique ids). */
function sameIdSet(expected: readonly string[], actual: readonly string[]): boolean {
  if (expected.length !== actual.length) return false;
  const want = new Set(expected);
  return want.size === expected.length && actual.every((id) => want.has(id));
}

export async function addPart(userId: string, bookingId: string, body: AddPartBody): Promise<{ id: string }> {
  const tech = await requireTechnician(userId);
  const booking = await ownOpenCartBookingOrThrow(tech.id, bookingId);
  const cat = await prisma.partsCatalog.findFirst({ where: { id: body.partsCatalogId, deletedAt: null, status: 'ACTIVE' } });
  if (!cat) throw new NotFoundError('Part not found');
  // A category-scoped part must match the booking's service category (no padding the cart with
  // unrelated parts to inflate the estimate). A null categoryId is a generic part — allowed anywhere.
  if (cat.categoryId !== null && cat.categoryId !== booking.service.categoryId) {
    throw new UnprocessableError('This part does not apply to this service category');
  }
  const line = await prisma.$transaction(async (tx) => {
    // Re-assert ARRIVED inside the tx (optimistic guard): if "Submit diagnosis" committed concurrently the cart is frozen, so this matches 0 rows → reject.
    // It also takes the booking row lock, so concurrent adds serialize here and the two checks below read the committed cart.
    await assertCartStillOpen(tx, bookingId);
    // One line per part (qty is the only multiplier, capped by the schema) and a bounded line count —
    // a technician cannot pad the estimate with repeated lines of the same part.
    const existing = await tx.bookingPart.findMany({ where: { bookingId }, select: { partsCatalogId: true } });
    if (existing.some((l) => l.partsCatalogId === cat.id)) throw new ConflictError(DUPLICATE_PART_MESSAGE);
    if (existing.length >= MAX_CART_LINES) throw new UnprocessableError(`An estimate can list at most ${MAX_CART_LINES} parts`);
    const created = await tx.bookingPart.create({
      data: { bookingId, partsCatalogId: cat.id, sku: cat.sku, name: cat.name, ceilingPricePaise: cat.ceilingPricePaise, qty: body.qty },
    });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'part_added', lineId: created.id, sku: created.sku, qty: created.qty, ceilingPricePaise: created.ceilingPricePaise } } });
    return created;
  });
  return { id: line.id };
}

/** Optimistic freeze guard: a no-op update conditional on the booking still being in `state`.
 *  0 rows affected means a concurrent transition already moved the booking on → the write is stale. */
async function assertStillInState(
  tx: import('@prisma/client').Prisma.TransactionClient,
  bookingId: string,
  state: 'ARRIVED' | 'DIAGNOSED' | 'REPAIR_IN_PROGRESS',
  message: string,
): Promise<void> {
  const r = await tx.booking.updateMany({ where: { id: bookingId, state }, data: { updatedAt: new Date() } });
  if (r.count === 0) throw new ConflictError(message);
}

/** Cart freeze: a concurrent "Submit diagnosis" already moved the booking out of ARRIVED. */
async function assertCartStillOpen(tx: import('@prisma/client').Prisma.TransactionClient, bookingId: string): Promise<void> {
  await assertStillInState(tx, bookingId, 'ARRIVED', CART_LOCKED_MESSAGE);
}

export async function removePart(userId: string, bookingId: string, partId: string): Promise<void> {
  const tech = await requireTechnician(userId);
  await ownOpenCartBookingOrThrow(tech.id, bookingId);
  const line = await prisma.bookingPart.findFirst({ where: { id: partId, bookingId } });
  if (!line) throw new NotFoundError('Part line not found');
  await prisma.$transaction(async (tx) => {
    await assertCartStillOpen(tx, bookingId);
    // deleteMany (scoped to {id, bookingId}) is idempotent — a concurrent double-remove deletes 0 rows
    // instead of throwing Prisma P2025; the findFirst above already established the 404 case.
    const deleted = await tx.bookingPart.deleteMany({ where: { id: partId, bookingId } });
    // Audit only a real removal (the losing side of a double-remove changed nothing). The line is
    // hard-deleted, so the audit carries its snapshot.
    if (deleted.count > 0) {
      await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'part_removed', lineId: line.id, sku: line.sku, qty: line.qty, ceilingPricePaise: line.ceilingPricePaise } } });
    }
  });
}

/** CUSTOMER_APPROVED → PARTS_REQUESTED. Only honest with a non-empty approved cart. */
export async function partsNeeded(userId: string, bookingId: string): Promise<{ id: string; state: 'PARTS_REQUESTED' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'CUSTOMER_APPROVED');
  await prisma.$transaction(async (tx) => {
    // Count inside the tx so the audit's partCount is exactly the gated set (the cart is frozen once
    // the diagnosis is submitted anyway, but the in-tx read keeps the gate and its evidence atomic).
    const partCount = await tx.bookingPart.count({ where: { bookingId } });
    if (partCount === 0) throw new UnprocessableError('No parts in the approved estimate — start the repair instead');
    await transitionBooking(tx, booking, 'PARTS_REQUESTED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { partCount });
  });
  return { id: bookingId, state: 'PARTS_REQUESTED' };
}

/** PARTS_REQUESTED → PARTS_ACQUIRED (merchant procurement is WhatsApp-manual in V1 — tracked only). */
export async function partsAcquired(userId: string, bookingId: string): Promise<{ id: string; state: 'PARTS_ACQUIRED' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'PARTS_REQUESTED');
  await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'PARTS_ACQUIRED', { type: 'USER', kind: 'TECHNICIAN', id: userId }),
  );
  return { id: bookingId, state: 'PARTS_ACQUIRED' };
}

/** CUSTOMER_APPROVED | PARTS_ACQUIRED → REPAIR_IN_PROGRESS. Opens the repair-photo window. */
export async function startRepair(userId: string, bookingId: string): Promise<{ id: string; state: 'REPAIR_IN_PROGRESS' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, ['CUSTOMER_APPROVED', 'PARTS_ACQUIRED'] as const);
  await prisma.$transaction(async (tx) => {
    await transitionBooking(tx, booking, 'REPAIR_IN_PROGRESS', { type: 'USER', kind: 'TECHNICIAN', id: userId });
    await tx.booking.update({ where: { id: bookingId }, data: { repairStartedAt: new Date() } });
  });
  return { id: bookingId, state: 'REPAIR_IN_PROGRESS' };
}

/** REPAIR_IN_PROGRESS → REPAIR_COMPLETE. Gated on ALL 3 repair photos (Rule 1: no photos = no
 *  completion = no payment). Booking row locked first so the gate reads the final committed set. */
export async function completeRepair(userId: string, bookingId: string): Promise<{ id: string; state: 'REPAIR_COMPLETE' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'REPAIR_IN_PROGRESS');
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: { repairCompletedAt: new Date() } });
    const activePhotos = await tx.photoEvidence.findMany({
      where: { bookingId, deletedAt: null, kind: { in: [...REPAIR_KINDS] } },
      select: { id: true, kind: true },
    });
    const slots = new Set(activePhotos.map((p) => p.kind));
    if (!REPAIR_KINDS.every((k) => slots.has(k))) {
      throw new UnprocessableError('3 repair photos required (old part removed, new packaging, installed)');
    }
    await transitionBooking(tx, booking, 'REPAIR_COMPLETE', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { photoIds: activePhotos.map((p) => p.id) });
  });
  return { id: bookingId, state: 'REPAIR_COMPLETE' };
}

/** One owner for the R2 key shape: sign BUILDS with this prefix, confirm VERIFIES against it —
 *  a change to the layout cannot drift between the two (B5's repair kinds reuse both paths). */
function photoKeyPrefix(bookingId: string, kind: PhotoKindValue): string {
  return `jobs/${bookingId}/${kind}-`;
}

/** Mirrors photoKeyPrefix's shape: jobs/<bookingId>/<KIND>-<rest>.jpg. */
const PHOTO_KEY_PATTERN = /^jobs\/([^/]+)\/([A-Z_]+)-[^/.]+\.jpg$/;

/**
 * Dev-only tooling's ownership guard (finding 8; CLAUDE.md "verify ownership, not just
 * authentication"): the dev mark-uploaded hook lets its caller mark ANY key as uploaded, so without
 * this, any authenticated technician (or non-technician) could mark evidence for a job that isn't
 * theirs. Parses the bookingId/kind out of the key, then re-runs the same checks the real photo
 * routes use. No state-window check — confirm re-asserts that itself.
 */
export async function assertTechnicianOwnsPhotoKey(userId: string, key: string): Promise<void> {
  const match = PHOTO_KEY_PATTERN.exec(key);
  const kindCandidate = match?.[2];
  if (!match || !kindCandidate || !photoKind.safeParse(kindCandidate).success) {
    throw new UnprocessableError('Invalid photo key');
  }
  const bookingId = match[1]!;
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, select: { technicianId: true } });
  if (!booking) throw new NotFoundError('Job not found', JOB_NOT_FOUND);
  if (booking.technicianId !== tech.id) throw new ForbiddenError('This job is not assigned to you', JOB_NOT_ASSIGNED);
}

/** Presign a photo upload slot. Window is determined by kind (DIAGNOSIS_* in ARRIVED, REPAIR_* in REPAIR_IN_PROGRESS). */
export async function signPhotoUpload(userId: string, bookingId: string, body: SignPhotoBody): Promise<{ url: string; key: string; expiresAt: string }> {
  const tech = await requireTechnician(userId);
  await ownAssignedBookingOrThrow(tech.id, bookingId, PHOTO_WINDOW[body.kind]);
  const key = `${photoKeyPrefix(bookingId, body.kind)}${randomUUID()}.jpg`;
  const { url, expiresAt } = await photoStorage.presignUpload(key, body.contentLengthBytes);
  return { url, key, expiresAt: expiresAt.toISOString() };
}

/** Confirm an uploaded photo: HEAD-verified (evidence must EXIST, not be claimed — Golden Rule 1),
 *  booking-scoped key, replace-by-soft-delete per (booking, kind), audited in-tx. */
export async function confirmPhoto(userId: string, bookingId: string, body: ConfirmPhotoBody): Promise<{ id: string; kind: ConfirmPhotoBody['kind']; capturedAt: string }> {
  const tech = await requireTechnician(userId);
  await ownAssignedBookingOrThrow(tech.id, bookingId, PHOTO_WINDOW[body.kind]);
  // Key must match this booking AND this slot — sign bakes the kind into the key, so a single
  // uploaded object cannot be confirmed into BOTH slots (2 photos means two DISTINCT photos).
  if (!body.key.startsWith(photoKeyPrefix(bookingId, body.kind))) throw new UnprocessableError('Key does not belong to this booking and slot');
  if (!(await photoStorage.objectExists(body.key))) throw new UnprocessableError('Upload not found — PUT the photo to the signed URL first');

  const created = await prisma.$transaction(async (tx) => {
    // Re-assert the capture window inside the tx (same freeze idiom as the cart): a concurrent
    // transition must not race a photo replacement in — the photos counted by the gate are the ones that stay.
    await assertStillInState(tx, bookingId, PHOTO_WINDOW[body.kind], 'Photos can only be confirmed during their capture window — the booking has moved on');
    // Retake = replace: soft-delete the previous active row for this slot (evidence trail kept).
    const replaced = await tx.photoEvidence.updateMany({ where: { bookingId, kind: body.kind, deletedAt: null }, data: { deletedAt: new Date() } });
    const row = await tx.photoEvidence.create({
      data: { bookingId, kind: body.kind, r2Key: body.key, geotagLat: body.geotagLat ?? null, geotagLng: body.geotagLng ?? null, capturedAt: new Date(body.capturedAt) },
    });
    // No coords in audit (Rule 7) — only whether a geotag exists.
    await tx.auditLog.create({
      data: { action: 'PHOTO_UPLOADED', actorType: 'USER', actorId: userId, metadata: { bookingId, kind: body.kind, hasGeotag: body.geotagLat != null, replaced: replaced.count > 0 } },
    });
    return row;
  });
  return { id: created.id, kind: body.kind, capturedAt: created.capturedAt.toISOString() };
}

/** REPAIR_COMPLETE → CUSTOMER_CONFIRMED (keystone #2), and zero-payable chain → PAYMENT_RECEIVED.
 *  The technician drives the transition but ONLY with the code minted to the customer's phone —
 *  no single-party path (Rule 2).
 *  NOTE: a correct code is consumed BEFORE the tx (redis and Postgres can't share one); if the tx
 *  rolled back the customer just re-requests — fails SAFE, never a false CUSTOMER_CONFIRMED
 *  (same accepted trade-off as the arrival handshake).
 *  B6c zero-payable chain: when the visit-fee credit covers the whole job there is nothing to
 *  charge — never show the customer a ₹0 pay screen. The second transition runs in the SAME tx
 *  so a crash can't strand the booking between the two states. */
export async function confirmCompletion(userId: string, bookingId: string, body: ConfirmCompletionBody): Promise<{ id: string; state: 'CUSTOMER_CONFIRMED' | 'PAYMENT_RECEIVED' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'REPAIR_COMPLETE');
  const result = await verifyCompletionCode(bookingId, body.code);
  if (result === 'no-code') throw new ConflictError('No active code — ask the customer to request one');
  if (result === 'invalid') throw new UnauthorizedError('Invalid or expired completion code');
  const finalState = await prisma.$transaction(async (tx) => {
    await transitionBooking(tx, booking, 'CUSTOMER_CONFIRMED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { codeConfirmed: true });
    await tx.booking.update({ where: { id: bookingId }, data: { confirmedAt: new Date() } });
    // Zero-payable chain (B6c): when the visit-fee credit covers the whole job there is nothing
    // to charge — never show the customer a ₹0 pay screen. Same tx: a crash can't strand the
    // booking between the two states.
    const cart = await tx.bookingPart.findMany({ where: { bookingId } });
    // Pass 'CUSTOMER_CONFIRMED' (the post-transition state) not booking.state — booking.state is
    // still REPAIR_COMPLETE here, and computeEstimate applies the visit-fee credit only post-quote.
    const payable = computeEstimate({ laborPaise: booking.laborPaise, visitFeePaise: booking.visitFeePaise, state: 'CUSTOMER_CONFIRMED', declinedAt: booking.declinedAt }, cart).totalPayablePaise;
    if (payable > 0) return 'CUSTOMER_CONFIRMED' as const;
    // { ...booking, state: 'CUSTOMER_CONFIRMED' } so the second optimistic lock (WHERE state=...)
    // matches the row the first transition just committed in THIS tx — not the stale REPAIR_COMPLETE.
    await transitionBooking(tx, { ...booking, state: 'CUSTOMER_CONFIRMED' }, 'PAYMENT_RECEIVED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'zero-payable' }, { amountPaise: 0, reason: 'zero_payable' });
    await tx.booking.update({ where: { id: bookingId }, data: { paidAt: new Date() } });
    return 'PAYMENT_RECEIVED' as const;
  });
  return { id: bookingId, state: finalState };
}

/** Cash receipt (B6b): CUSTOMER_CONFIRMED or DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED. The
 *  technician drives the transition but ONLY with the receipt code minted to the customer's phone
 *  (Rule 2). The code is consumed BEFORE the tx (redis and Postgres can't share one) — if the tx
 *  rolls back the customer re-initiates; fails SAFE, never a false capture (completion idiom).
 *  Gates re-run INSIDE the tx: the debt increment locks the technician row first, so concurrent
 *  captures serialize and the checks read a settled world (initiation-time checks are only UX). */
export async function confirmCashPayment(userId: string, bookingId: string, body: ConfirmCashBody): Promise<{ id: string; state: 'PAYMENT_RECEIVED'; cashDebtPaise: number }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, ['CUSTOMER_CONFIRMED', 'DECLINED_BY_CUSTOMER'] as const);
  const r = await verifyCashReceiptCode(bookingId, body.code);
  if (r.status === 'no-code') throw new ConflictError('No active code — ask the customer to start the cash payment');
  if (r.status === 'invalid') throw new UnauthorizedError('Invalid or expired cash receipt code');
  const { paymentId, amountPaise } = r.payload;

  const cashDebtPaise = await prisma.$transaction(async (tx) => {
    // Increment FIRST: the technician-row update is the lock serializing this technician's captures.
    const t = await tx.technician.update({
      where: { id: tech.id },
      data: { cashDebtPaise: { increment: amountPaise } },
      select: { cashDebtPaise: true },
    });
    if (t.cashDebtPaise > config.CASH_DEBT_LIMIT_PAISE) {
      throw new UnprocessableError('Outstanding cash debt limit reached — please pay by UPI');
    }
    // Assumes READ COMMITTED (Postgres default): the row lock above serializes same-technician
    // captures, so this aggregate reads every PRIOR capture committed. Under REPEATABLE READ the
    // re-read would see a stale snapshot and the cap could be jointly exceeded — do not change
    // the DB isolation level without revisiting this.
    if ((await cashCollectedLast24hPaise(tx, tech.id)) + amountPaise > config.CASH_VELOCITY_CAP_PAISE) {
      throw new UnprocessableError('Daily cash collection limit reached — please pay by UPI');
    }
    // Keyed on CREATED: a superseded/settled attempt can never capture twice.
    const updated = await tx.payment.updateMany({ where: { id: paymentId, status: 'CREATED' }, data: { status: 'CAPTURED', capturedAt: new Date() } });
    if (updated.count === 0) throw new ConflictError('This payment is no longer open');
    // Payment guard (CREATED status) + booking state guard: either race-loss rolls back the WHOLE tx including debt increment.
    await transitionBooking(tx, booking, 'PAYMENT_RECEIVED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { method: 'CASH', amountPaise, codeConfirmed: true });
    await tx.booking.update({ where: { id: bookingId }, data: { paidAt: new Date() } }); // the close sweep (B6c) keys on this
    await tx.auditLog.create({
      data: { action: 'PAYMENT_EVENT', actorType: 'USER', actorId: userId, metadata: { event: 'cash_received', bookingId, paymentId, amountPaise, technicianId: tech.id } },
    });
    await recordCashCollected(tx, { technicianId: tech.id, bookingId, amountPaise });
    return t.cashDebtPaise;
  });
  return { id: bookingId, state: 'PAYMENT_RECEIVED', cashDebtPaise };
}
