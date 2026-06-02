import { z } from 'zod';

/** Roles that may self-register via OTP (Merchant/Admin use other paths). */
export const otpRole = z.enum(['CUSTOMER', 'TECHNICIAN']);

const phone = z.string().regex(/^[6-9]\d{9}$/, 'Invalid Indian phone number');

export const sendOtpBody = z.object({ phone, role: otpRole });
export type SendOtpBody = z.infer<typeof sendOtpBody>;

// NOTE: `role` is accepted for symmetry with the send request, but it is IGNORED
// for an existing user — their stored role always wins (see verifyOtp). It only
// affects which profile is created for a brand-new phone (the role captured at send).
export const verifyOtpBody = z.object({
  phone,
  role: otpRole,
  otp: z.string().regex(/^\d{6}$/, 'OTP must be 6 digits'),
});
export type VerifyOtpBody = z.infer<typeof verifyOtpBody>;

export const refreshBody = z.object({ refreshToken: z.string().min(1) });
export type RefreshBody = z.infer<typeof refreshBody>;

export const logoutBody = z.object({ refreshToken: z.string().min(1) });
export type LogoutBody = z.infer<typeof logoutBody>;
