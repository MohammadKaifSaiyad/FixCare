import { config } from '../../shared/config.js';
import { mintOtp, verifyOtp as verifyOtpStore } from '../../shared/auth/otp-store.js';
import { verifyPassword } from '../../shared/auth/argon2.js';
import { TooManyRequestsError, UnauthorizedError, ForbiddenError } from '../../shared/errors.js';
import { makeOtpSender } from '../../shared/third-party/otp-sender.js';
import { prisma } from '../../shared/database/prisma.js';
import type { Prisma, UserRole } from '@prisma/client';
import { signAccessToken, issueRefreshToken, hashRefreshToken } from '../../shared/auth/tokens.js';
import { toUserDto, toAdminDto, type AuthTokens, type AdminAuthTokens } from './auth.types.js';
import type { SendOtpBody, VerifyOtpBody, RefreshBody, LogoutBody, AdminLoginBody } from './auth.schemas.js';

const otpSender = makeOtpSender();

const otpKey = (phone: string) => `otp:${phone}`;

export interface SendOtpResult {
  ok: true;
  devOtp?: string;
}

export async function sendOtp({ phone, role }: SendOtpBody): Promise<SendOtpResult> {
  const r = await mintOtp<{ role: UserRole }>(
    otpKey(phone),
    {
      ttlSeconds: config.OTP_TTL_SECONDS,
      sendLimit: { max: config.OTP_MAX_SENDS_PER_WINDOW, windowSeconds: config.OTP_SEND_WINDOW_SECONDS },
    },
    { role },
  );
  if (r.status === 'throttled') {
    throw new TooManyRequestsError('Too many OTP requests. Try again later.');
  }
  await otpSender.send(phone, r.code);
  return config.NODE_ENV === 'production' ? { ok: true } : { ok: true, devOtp: r.code };
}

/** Create a User + exactly the matching role profile, atomically. The ONLY user-creation path. */
export async function createUserWithProfile(tx: Prisma.TransactionClient, phone: string, role: UserRole) {
  const user = await tx.user.create({ data: { phone, role } });
  if (role === 'CUSTOMER') await tx.customer.create({ data: { userId: user.id, name: '' } });
  else if (role === 'TECHNICIAN') await tx.technician.create({ data: { userId: user.id, name: '', skills: [] } });
  else throw new ForbiddenError('Role cannot self-register via OTP');
  return user;
}

export async function verifyOtp({ phone, otp }: VerifyOtpBody): Promise<AuthTokens> {
  const r = await verifyOtpStore<{ role: UserRole }>(otpKey(phone), otp, {
    maxAttempts: config.OTP_MAX_VERIFY_ATTEMPTS,
  });
  // Auth folds every failure mode into one generic 401 (no enumeration of why). The !r.payload
  // guard also covers a key stored without a payload (e.g. a pre-refactor in-flight OTP whose
  // role lived at the top level) — better a 401 + fresh OTP than a destructuring crash.
  if (r.status !== 'ok' || !r.payload) throw new UnauthorizedError('Invalid or expired OTP');
  const { role } = r.payload;

  return prisma.$transaction(async (tx) => {
    const existing = await tx.user.findUnique({ where: { phone } });
    let user = existing;
    let isNew = false;
    if (!existing) {
      user = await createUserWithProfile(tx, phone, role);
      isNew = true;
    } else if (existing.status !== 'ACTIVE' || existing.deletedAt) {
      throw new ForbiddenError('Account is not active');
    }
    await tx.auditLog.create({
      data: { action: isNew ? 'USER_REGISTERED' : 'USER_LOGGED_IN', actorType: 'USER', actorId: user!.id },
    });
    const accessToken = signAccessToken(user!.id, user!.role);
    const { raw: refreshToken } = await issueRefreshToken(tx, user!.id);
    return { accessToken, refreshToken, user: toUserDto(user!) };
  });
}

export async function refreshTokens({ refreshToken }: RefreshBody): Promise<{ accessToken: string; refreshToken: string }> {
  const tokenHash = hashRefreshToken(refreshToken);

  const existing = await prisma.refreshToken.findUnique({ where: { tokenHash } });
  if (!existing) throw new UnauthorizedError('Invalid refresh token');

  // Reuse-detection: a revoked token presented again = theft signal. These side
  // effects must persist (not roll back with the 401), so they commit in their own
  // transaction before we throw.
  if (existing.revokedAt) {
    await prisma.$transaction(async (tx) => {
      await tx.refreshToken.updateMany({
        where: { userId: existing.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      await tx.auditLog.create({
        data: { action: 'REFRESH_TOKEN_REUSE_DETECTED', actorType: 'SYSTEM', subjectId: existing.userId },
      });
    });
    throw new UnauthorizedError('Invalid refresh token');
  }

  if (existing.expiresAt < new Date()) throw new UnauthorizedError('Invalid refresh token');

  // Rotate: issue new, revoke + link old.
  // NOTE: a legitimate near-simultaneous double-fire could present the same token
  // twice; we accept the rare re-login rather than add a grace window in V1.
  return prisma.$transaction(async (tx) => {
    const user = await tx.user.findUniqueOrThrow({ where: { id: existing.userId } });
    const { raw, id: newId } = await issueRefreshToken(tx, existing.userId);
    await tx.refreshToken.update({ where: { id: existing.id }, data: { revokedAt: new Date(), replacedById: newId } });
    const accessToken = signAccessToken(user.id, user.role);
    return { accessToken, refreshToken: raw };
  });
}

/** Revoke a single refresh token (idempotent — no error if already gone/revoked). */
export async function logout({ refreshToken }: LogoutBody): Promise<void> {
  const tokenHash = hashRefreshToken(refreshToken);
  await prisma.refreshToken.updateMany({ where: { tokenHash, revokedAt: null }, data: { revokedAt: new Date() } });
}

/** Revoke all of a user's active refresh tokens ("log out all devices"). */
export async function logoutAll(userId: string): Promise<void> {
  await prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
}

export async function adminLogin({ email, password }: AdminLoginBody): Promise<AdminAuthTokens> {
  const admin = await prisma.admin.findUnique({ where: { email }, include: { user: true } });

  // Generic 401 for BOTH unknown email and wrong password (no account enumeration).
  const ok = admin ? await verifyPassword(admin.passwordHash, password) : false;
  if (!admin || !ok) throw new UnauthorizedError('Invalid email or password');

  // Only revealed AFTER a correct password (so the 403 doesn't leak account existence).
  if (admin.status !== 'ACTIVE' || admin.deletedAt || admin.user.status !== 'ACTIVE' || admin.user.deletedAt) {
    throw new ForbiddenError('Account is not active');
  }

  return prisma.$transaction(async (tx) => {
    await tx.auditLog.create({ data: { action: 'USER_LOGGED_IN', actorType: 'ADMIN', actorId: admin.user.id } });
    const accessToken = signAccessToken(admin.user.id, admin.user.role);
    const { raw: refreshToken } = await issueRefreshToken(tx, admin.user.id);
    return { accessToken, refreshToken, admin: toAdminDto(admin) };
  });
}
