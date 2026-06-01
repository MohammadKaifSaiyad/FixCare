import { createHash, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import type { Prisma, UserRole } from '@prisma/client';
import { config } from '../config.js';

export interface AccessClaims {
  sub: string;
  role: UserRole;
}

/** Sign a short-lived access JWT (HS256). */
export function signAccessToken(userId: string, role: UserRole): string {
  return jwt.sign({ sub: userId, role } satisfies AccessClaims, config.JWT_SECRET, {
    algorithm: 'HS256',
    expiresIn: config.JWT_ACCESS_TTL,
  } as jwt.SignOptions);
}

/** SHA-256 of a refresh token (only the hash is stored). */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Issue a new refresh token: returns the raw opaque token (sent to client) and
 * creates the hashed RefreshToken row. NOTE: rotation/reuse-detection are sub-slice B.
 */
export async function issueRefreshToken(
  tx: Prisma.TransactionClient,
  userId: string,
  meta: { userAgent?: string; ipHash?: string } = {},
): Promise<string> {
  const raw = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + config.REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000);
  await tx.refreshToken.create({
    data: { userId, tokenHash: hashRefreshToken(raw), expiresAt, userAgent: meta.userAgent, ipHash: meta.ipHash },
  });
  return raw;
}
