import { createHash, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import type { Prisma, UserRole } from '@prisma/client';
import { config } from '../config.js';
import { UnauthorizedError } from '../errors.js';

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

/** Verify an access JWT (HS256). Throws UnauthorizedError on any invalid/expired token. */
export function verifyAccessToken(token: string): AccessClaims {
  try {
    const decoded = jwt.verify(token, config.JWT_SECRET, { algorithms: ['HS256'] });
    if (typeof decoded === 'string' || !decoded.sub || !('role' in decoded)) {
      throw new UnauthorizedError('Invalid token');
    }
    return { sub: String(decoded.sub), role: (decoded as { role: UserRole }).role };
  } catch (err) {
    if (err instanceof UnauthorizedError) throw err;
    throw new UnauthorizedError('Invalid or expired token');
  }
}

/** SHA-256 of a refresh token (only the hash is stored). */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export interface IssuedRefreshToken {
  raw: string;   // sent to the client
  id: string;    // RefreshToken row id (for rotation linking)
}

/** Create a new refresh-token row (hashed) with a sliding 30d expiry. Returns the raw token + row id. */
export async function issueRefreshToken(
  tx: Prisma.TransactionClient,
  userId: string,
  meta: { userAgent?: string; ipHash?: string } = {},
): Promise<IssuedRefreshToken> {
  const raw = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + config.REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000);
  const row = await tx.refreshToken.create({
    data: { userId, tokenHash: hashRefreshToken(raw), expiresAt, userAgent: meta.userAgent, ipHash: meta.ipHash },
  });
  return { raw, id: row.id };
}
