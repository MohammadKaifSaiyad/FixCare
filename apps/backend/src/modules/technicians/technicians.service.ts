import type { Prisma, Technician, TechnicianStatus } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ConflictError, NotFoundError, UnprocessableError } from '../../shared/errors.js';
import { findActiveZones, zoneRefs } from '../catalog/catalog.service.js';
import { countActiveJobsForTechnician } from '../bookings/bookings.state.js';
import { countLiveCashAttemptsForTechnician } from '../bookings/cash.js';
import type { ZoneRef } from '../catalog/catalog.types.js';
import { toAdminTechnicianDto, toTechnicianProfileDto, type AdminTechnicianDto, type TechnicianProfileDto } from './technicians.types.js';
import type { AdminTechnicianPatchBody, TechnicianPatchBody } from './technicians.schemas.js';
import { applyTechnicianTransition, INVALID_TECHNICIAN_TRANSITION, TECHNICIAN_TRANSITIONS, type TechnicianReviewAction } from './technicians.lifecycle.js';

/** The technician's own edits are allowed only while PENDING (new, or sent back by ops). */
export const PROFILE_LOCKED = 'PROFILE_LOCKED';

type Db = Prisma.TransactionClient | typeof prisma;

export async function zoneIdsOf(db: Db, technicianId: string): Promise<string[]> {
  const rows = await db.technicianZone.findMany({ where: { technicianId }, select: { zoneId: true } });
  return rows.map((r) => r.zoneId);
}

/** The technician's service-zone ids — dispatch (technician-jobs) offers only bookings in these zones. */
export async function technicianZoneIds(technicianId: string): Promise<string[]> {
  return zoneIdsOf(prisma, technicianId);
}

export async function replaceZones(tx: Prisma.TransactionClient, technicianId: string, zoneIds: readonly string[]): Promise<void> {
  await tx.technicianZone.deleteMany({ where: { technicianId } });
  await tx.technicianZone.createMany({ data: zoneIds.map((zoneId) => ({ technicianId, zoneId })) });
}

/** Every id must be an ACTIVE, non-deleted zone (ids are unique — Zod enforces it). */
export async function assertActiveZones(zoneIds: readonly string[]): Promise<void> {
  const found = await findActiveZones(zoneIds);
  if (found.length !== zoneIds.length) throw new UnprocessableError('Choose service zones from the list');
}

export async function toProfileDto(t: Technician): Promise<TechnicianProfileDto> {
  return toTechnicianProfileDto(t, await zoneRefs(await zoneIdsOf(prisma, t.id)));
}

export async function getTechnicianProfile(userId: string): Promise<TechnicianProfileDto> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!t) throw new NotFoundError('Profile not found');
  return toProfileDto(t);
}

export async function updateOwnTechnicianProfile(userId: string, patch: TechnicianPatchBody): Promise<TechnicianProfileDto> {
  const fields = Object.keys(patch); // field NAMES only — never the values (no PII in audit)
  const { zoneIds, ...columns } = patch;
  if (zoneIds) {
    // A locked profile answers PROFILE_LOCKED even for a bad zone (the guarded update below is the real lock).
    const current = await prisma.technician.findFirst({ where: { userId, deletedAt: null }, select: { status: true } });
    if (current && current.status !== 'PENDING') throw new ConflictError('Your profile is locked while under review', PROFILE_LOCKED);
    // Pre-tx validation (a read of another module's data): a zone deactivated in the gap is caught again at submit.
    await assertActiveZones(zoneIds);
  }
  const updated = await prisma.$transaction(async (tx) => {
    const existing = await tx.technician.findFirst({ where: { userId, deletedAt: null } });
    if (!existing) throw new NotFoundError('Profile not found');
    // The UPDATE itself re-checks PENDING, so a submit racing this edit can't slip a change past the lock.
    // updatedAt is set explicitly so the statement always runs (even for a zones-only edit).
    const res = await tx.technician.updateMany({ where: { id: existing.id, status: 'PENDING' }, data: { ...columns, updatedAt: new Date() } });
    if (res.count === 0) throw new ConflictError('Your profile is locked while under review', PROFILE_LOCKED);
    if (zoneIds) await replaceZones(tx, existing.id, zoneIds);
    await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: userId, subjectId: existing.id, metadata: { fields } } });
    return tx.technician.findUniqueOrThrow({ where: { id: existing.id } });
  });
  return toProfileDto(updated);
}

export async function submitForReview(userId: string): Promise<TechnicianProfileDto> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!t) throw new NotFoundError('Profile not found');
  if (t.status !== 'PENDING') throw new ConflictError(TECHNICIAN_TRANSITIONS.submit.refused, INVALID_TECHNICIAN_TRANSITION);
  if (!t.name.trim()) throw new UnprocessableError('Add your name before submitting');
  if (t.skills.length === 0) throw new UnprocessableError('Choose at least one skill before submitting');
  const zoneIds = await zoneIdsOf(prisma, t.id);
  if (zoneIds.length === 0) throw new UnprocessableError('Choose at least one service zone before submitting');
  if ((await findActiveZones(zoneIds)).length !== zoneIds.length) {
    throw new UnprocessableError('One of your service zones is no longer available — update your zones and submit again');
  }
  await prisma.$transaction((tx) => applyTechnicianTransition(tx, t.id, 'submit', { type: 'USER', id: userId }));
  return getTechnicianProfile(userId);
}

const adminInclude = { user: { select: { phone: true } }, zones: { select: { zoneId: true } } } satisfies Prisma.TechnicianInclude;
type AdminRow = Prisma.TechnicianGetPayload<{ include: typeof adminInclude }>;

async function toAdminDtos(rows: AdminRow[]): Promise<AdminTechnicianDto[]> {
  const refs = await zoneRefs([...new Set(rows.flatMap((r) => r.zones.map((z) => z.zoneId)))]);
  const byId = new Map(refs.map((z) => [z.id, z]));
  return rows.map((r) => {
    const zones = r.zones.map((z) => byId.get(z.zoneId)).filter((z): z is ZoneRef => z !== undefined);
    return toAdminTechnicianDto(r, r.user.phone, zones.sort((a, b) => a.name.localeCompare(b.name)));
  });
}

async function getAdminTechnician(technicianId: string): Promise<AdminTechnicianDto> {
  const row = await prisma.technician.findFirst({ where: { id: technicianId, deletedAt: null }, include: adminInclude });
  if (!row) throw new NotFoundError('Technician not found');
  return (await toAdminDtos([row]))[0]!;
}

/** Ops' review queue: oldest submission first (never-submitted last), then oldest account. */
export async function listTechnicians(status?: TechnicianStatus): Promise<AdminTechnicianDto[]> {
  const rows = await prisma.technician.findMany({
    where: { deletedAt: null, ...(status ? { status } : {}) },
    include: adminInclude,
    orderBy: [{ submittedAt: { sort: 'asc', nulls: 'last' } }, { createdAt: 'asc' }],
  });
  return toAdminDtos(rows);
}

export async function reviewTechnician(
  adminUserId: string,
  technicianId: string,
  action: Exclude<TechnicianReviewAction, 'submit'>,
  reason?: string,
): Promise<AdminTechnicianDto> {
  await prisma.$transaction(async (tx) => {
    const t = await tx.technician.findFirst({ where: { id: technicianId, deletedAt: null }, select: { id: true } });
    if (!t) throw new NotFoundError('Technician not found');
    // The guarded updateMany inside applyTechnicianTransition takes the technician row lock and flips the status FIRST.
    // acceptJob locks the same row, so the two transactions serialize: a suspend either sees the accepted job below
    // (and refuses, rolling the status back) or the accept sees SUSPENDED (and refuses).
    await applyTechnicianTransition(tx, technicianId, action, { type: 'ADMIN', id: adminUserId }, reason);
    if (action === 'suspend') {
      if ((await countActiveJobsForTechnician(tx, technicianId)) > 0) {
        throw new ConflictError('This technician has an active job — resolve it before suspending', 'TECHNICIAN_HAS_ACTIVE_JOB');
      }
      if ((await countLiveCashAttemptsForTechnician(tx, technicianId, new Date())) > 0) {
        throw new ConflictError('This technician is collecting a cash payment right now — try again in a few minutes', 'TECHNICIAN_COLLECTING_CASH');
      }
    }
  });
  return getAdminTechnician(technicianId);
}

/** Ops changes skills / zones in any status (the technician's own edits stop at submit). */
export async function adminUpdateTechnician(adminUserId: string, technicianId: string, patch: AdminTechnicianPatchBody): Promise<AdminTechnicianDto> {
  if (patch.zoneIds) await assertActiveZones(patch.zoneIds);
  await prisma.$transaction(async (tx) => {
    const t = await tx.technician.findFirst({ where: { id: technicianId, deletedAt: null }, select: { id: true, skills: true } });
    if (!t) throw new NotFoundError('Technician not found');
    const sortedIds = (ids: readonly string[]) => [...ids].sort();
    const beforeZoneIds = patch.zoneIds ? sortedIds(await zoneIdsOf(tx, t.id)) : undefined;
    const before = { ...(patch.skills ? { skills: t.skills } : {}), ...(beforeZoneIds ? { zoneIds: beforeZoneIds } : {}) };
    const after = { ...(patch.skills ? { skills: patch.skills } : {}), ...(patch.zoneIds ? { zoneIds: sortedIds(patch.zoneIds) } : {}) };
    if (patch.skills) await tx.technician.update({ where: { id: t.id }, data: { skills: patch.skills } });
    if (patch.zoneIds) await replaceZones(tx, t.id, patch.zoneIds);
    await tx.auditLog.create({
      data: { action: 'PROFILE_UPDATED', actorType: 'ADMIN', actorId: adminUserId, subjectId: t.id, metadata: { fields: Object.keys(patch), by: 'admin', before, after } },
    });
  });
  return getAdminTechnician(technicianId);
}
