import { redis } from '../../shared/redis/client.js';
import { config } from '../../shared/config.js';
import { generateOtp, hashOtp } from '../../shared/auth/otp.js';
import { TooManyRequestsError, UnauthorizedError, ForbiddenError } from '../../shared/errors.js';
import { makeOtpSender } from '../../shared/third-party/otp-sender.js';
import { prisma } from '../../shared/database/prisma.js';
import type { Prisma, UserRole } from '@prisma/client';
import { signAccessToken, issueRefreshToken } from '../../shared/auth/tokens.js';
import { toUserDto, type AuthTokens } from './auth.types.js';
import type { SendOtpBody, VerifyOtpBody } from './auth.schemas.js';

const otpSender = makeOtpSender();

const otpKey = (phone: string) => `otp:${phone}`;
const rlKey = (phone: string) => `otp-rl:${phone}`;

export interface SendOtpResult {
  ok: true;
  devOtp?: string;
}

export async function sendOtp({ phone, role }: SendOtpBody): Promise<SendOtpResult> {
  const count = await redis.incr(rlKey(phone));
  if (count === 1) await redis.expire(rlKey(phone), config.OTP_SEND_WINDOW_SECONDS);
  if (count > config.OTP_MAX_SENDS_PER_WINDOW) {
    throw new TooManyRequestsError('Too many OTP requests. Try again later.');
  }

  const otp = generateOtp();
  await redis.set(
    otpKey(phone),
    JSON.stringify({ hash: hashOtp(otp), attempts: 0, role }),
    'EX', config.OTP_TTL_SECONDS,
  );
  await otpSender.send(phone, otp);

  return config.NODE_ENV === 'production' ? { ok: true } : { ok: true, devOtp: otp };
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
  const raw = await redis.get(otpKey(phone));
  if (!raw) throw new UnauthorizedError('Invalid or expired OTP');

  const state = JSON.parse(raw) as { hash: string; attempts: number; role: UserRole };

  if (state.attempts >= config.OTP_MAX_VERIFY_ATTEMPTS) {
    await redis.del(otpKey(phone));
    throw new UnauthorizedError('Invalid or expired OTP');
  }
  if (hashOtp(otp) !== state.hash) {
    await redis.set(otpKey(phone), JSON.stringify({ ...state, attempts: state.attempts + 1 }), 'KEEPTTL');
    throw new UnauthorizedError('Invalid or expired OTP');
  }

  await redis.del(otpKey(phone)); // single-use

  return prisma.$transaction(async (tx) => {
    const existing = await tx.user.findUnique({ where: { phone } });
    let user = existing;
    let isNew = false;
    if (!existing) {
      user = await createUserWithProfile(tx, phone, state.role);
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
