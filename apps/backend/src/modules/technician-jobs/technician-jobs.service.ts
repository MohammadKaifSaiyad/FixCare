import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, ConflictError } from '../../shared/errors.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import { toTechnicianJobDto, type TechnicianJobDto } from './technician-jobs.types.js';

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
  const full = await prisma.booking.findUniqueOrThrow({
    where: { id: bookingId },
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
