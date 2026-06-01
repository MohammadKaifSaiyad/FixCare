import { z } from 'zod';

/** Roles that may self-register via OTP (Merchant/Admin use other paths). */
export const otpRole = z.enum(['CUSTOMER', 'TECHNICIAN']);

const phone = z.string().regex(/^[6-9]\d{9}$/, 'Invalid Indian phone number');

export const sendOtpBody = z.object({ phone, role: otpRole });
export type SendOtpBody = z.infer<typeof sendOtpBody>;

export const verifyOtpBody = z.object({
  phone,
  role: otpRole,
  otp: z.string().regex(/^\d{6}$/, 'OTP must be 6 digits'),
});
export type VerifyOtpBody = z.infer<typeof verifyOtpBody>;
