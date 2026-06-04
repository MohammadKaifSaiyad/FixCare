import { buildApp } from '../../src/app.js';

type App = Awaited<ReturnType<typeof buildApp>>;

/** Drive the real OTP flow to register a user and return a usable access token. */
export async function registerAndToken(app: App, phone: string, role: 'CUSTOMER' | 'TECHNICIAN') {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role, otp } });
  const body = verify.json() as { accessToken: string; user: { id: string } };
  return { token: body.accessToken, userId: body.user.id };
}
