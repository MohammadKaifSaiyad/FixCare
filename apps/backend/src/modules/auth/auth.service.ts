import { redis } from '../../shared/redis/client.js';
import { config } from '../../shared/config.js';
import { generateOtp, hashOtp } from '../../shared/auth/otp.js';
import { TooManyRequestsError } from '../../shared/errors.js';
import { makeOtpSender } from '../../shared/third-party/otp-sender.js';
import type { SendOtpBody } from './auth.schemas.js';

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
