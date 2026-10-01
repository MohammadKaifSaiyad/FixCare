import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../../shared/middleware/auth.js';
import { NotFoundError, ValidationError } from '../../shared/errors.js';
import { DevPhotoStorage, type PhotoStorage } from '../../shared/third-party/r2-storage.js';
import { assertTechnicianOwnsPhotoKey } from '../technician-jobs/technician-jobs.service.js';

/** Body for the dev photo hook. Strict: the key is the only accepted field. */
export const markUploadedBody = z.object({ key: z.string().min(1).max(512) }).strict();

/**
 * DEV-ONLY tooling. Locally there is no object store: `DevPhotoStorage` issues fake
 * `dev-r2.local` upload URLs, so the technician app cannot really PUT a photo. This route
 * stands in for that PUT (the app calls it instead) so photo confirm's HEAD-verify passes and
 * the diagnosis / repair photo gates can be exercised end-to-end on a dev machine (ADR-0007).
 *
 * Double-guarded so it can never fake evidence (Golden Rule 1) against real storage:
 *  1. `nodeEnv === 'production'` → the route is NOT registered at all.
 *  2. storage is not a `DevPhotoStorage` (e.g. real R2) → 404.
 * Authenticated like every other photo call. The key is never logged.
 */
export async function registerDevRoutes(
  app: FastifyInstance,
  opts: { storage: PhotoStorage; nodeEnv: string },
): Promise<void> {
  if (opts.nodeEnv === 'production') return;

  app.post('/dev/photos/mark-uploaded', { preHandler: [requireAuth] }, async (req, reply) => {
    const storage = opts.storage;
    if (!(storage instanceof DevPhotoStorage)) throw new NotFoundError('Not found');
    const p = markUploadedBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    // Ownership, not just auth (finding 8): only the technician this key's booking is assigned to
    // may mark it uploaded — a service call, per the inter-module rule (never a cross-module query).
    await assertTechnicianOwnsPhotoKey(req.user!.id, p.data.key);
    storage.markUploaded(p.data.key);
    return reply.code(204).send();
  });
}
