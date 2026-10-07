import type { Prisma, TechnicianStatus } from '@prisma/client';
import { ConflictError } from '../../shared/errors.js';

export const INVALID_TECHNICIAN_TRANSITION = 'INVALID_TECHNICIAN_TRANSITION';

export type TechnicianReviewAction = 'submit' | 'verify' | 'sendBack' | 'suspend' | 'reinstate';

/** The whole technician lifecycle. Anything not listed here is refused (409). DEACTIVATED is untouched. */
export const TECHNICIAN_TRANSITIONS: Record<TechnicianReviewAction, { from: TechnicianStatus; to: TechnicianStatus; refused: string }> = {
  submit:    { from: 'PENDING',       to: 'KYC_SUBMITTED', refused: 'Your profile has already been submitted' },
  verify:    { from: 'KYC_SUBMITTED', to: 'VERIFIED',      refused: 'Only a technician awaiting review can be verified or sent back' },
  sendBack:  { from: 'KYC_SUBMITTED', to: 'PENDING',       refused: 'Only a technician awaiting review can be verified or sent back' },
  suspend:   { from: 'VERIFIED',      to: 'SUSPENDED',     refused: 'Only a verified technician can be suspended' },
  reinstate: { from: 'SUSPENDED',     to: 'VERIFIED',      refused: 'Only a suspended technician can be reinstated' },
};

export interface TransitionActor { type: 'USER' | 'ADMIN'; id: string; }

/**
 * Move one technician along the lifecycle and write its audit row, inside the caller's transaction.
 * The UPDATE is guarded on the expected FROM status, so a racing double-submit / double-review loses with
 * 409 instead of transitioning (and auditing) twice.
 */
export async function applyTechnicianTransition(
  tx: Prisma.TransactionClient,
  technicianId: string,
  action: TechnicianReviewAction,
  actor: TransitionActor,
  reason?: string,
): Promise<void> {
  const { from, to, refused } = TECHNICIAN_TRANSITIONS[action];
  const now = new Date();
  const data: Prisma.TechnicianUpdateManyMutationInput = { status: to, updatedAt: now };
  if (action === 'submit') data.submittedAt = now; // reviewNote kept: the technician still sees what was asked
  else data.reviewedAt = now;
  if (action === 'sendBack' || action === 'suspend') {
    if (!reason) throw new Error(`${action} requires a reason`); // programming error — routes validate it
    data.reviewNote = reason;
  }
  if (action === 'verify' || action === 'reinstate') data.reviewNote = null;
  const res = await tx.technician.updateMany({ where: { id: technicianId, status: from, deletedAt: null }, data });
  if (res.count === 0) throw new ConflictError(refused, INVALID_TECHNICIAN_TRANSITION);
  await tx.auditLog.create({
    data: {
      action: 'TECHNICIAN_STATUS_CHANGED', actorType: actor.type, actorId: actor.id, subjectId: technicianId,
      metadata: { from, to, ...(reason ? { reason } : {}) },
    },
  });
}
