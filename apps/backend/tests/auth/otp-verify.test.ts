import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function sendAndGetOtp(phone: string, role: 'CUSTOMER' | 'TECHNICIAN') {
  const res = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role } });
  return res.json().devOtp as string;
}

describe('POST /auth/otp/verify', () => {
  it('new TECHNICIAN: creates User + exactly one Technician profile + returns tokens', async () => {
    const phone = '9800000010';
    const otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.user.role).toBe('TECHNICIAN');

    const user = await prisma.user.findUnique({ where: { phone }, include: { technician: true, customer: true } });
    expect(user?.technician).toBeTruthy();
    expect(user?.customer).toBeNull();
    const tokens = await prisma.refreshToken.count({ where: { userId: user!.id } });
    expect(tokens).toBe(1);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'USER_REGISTERED', actorId: user!.id } });
    expect(audit).toBeTruthy();
  });

  it('existing user, same role → logs in + audits USER_LOGGED_IN', async () => {
    const phone = '9800000011';
    let otp = await sendAndGetOtp(phone, 'CUSTOMER');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    otp = await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.role).toBe('CUSTOMER');
    const user = await prisma.user.findUniqueOrThrow({ where: { phone } });
    expect(await prisma.auditLog.count({ where: { action: 'USER_LOGGED_IN', actorId: user.id } })).toBe(1);
  });

  it('customer number in the technician app → 409 ROLE_MISMATCH; no tokens, no technician profile, OTP consumed', async () => {
    const phone = '9800000014';
    let otp = await sendAndGetOtp(phone, 'CUSTOMER');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'ROLE_MISMATCH', message: 'This number is registered as a customer. Please use the FixCare customer app.' });
    const user = await prisma.user.findUniqueOrThrow({ where: { phone }, include: { technician: true } });
    expect(user.role).toBe('CUSTOMER');
    expect(user.technician).toBeNull();
    expect(await prisma.refreshToken.count({ where: { userId: user.id } })).toBe(1); // only the first, real login
    expect(await prisma.auditLog.count({ where: { action: 'USER_LOGGED_IN', actorId: user.id } })).toBe(0);
    const again = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(again.statusCode).toBe(401);
  });

  it('technician number in the customer app → 409 with the FixCare Pro message', async () => {
    const phone = '9800000015';
    let otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    otp = await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'ROLE_MISMATCH', message: 'This number is registered as a FixCare technician. Please use the FixCare Pro app.' });
    expect(await prisma.customer.count()).toBe(0);
  });

  it("an admin's number in either app → 409 with the neutral message", async () => {
    const phone = '9800000016';
    await prisma.user.create({ data: { phone, role: 'ADMIN' } });
    const otp = await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    expect(res.json()).toEqual({ code: 'ROLE_MISMATCH', message: "This number can't be used to sign in here." });
  });

  it('wrong OTP → 401', async () => {
    const phone = '9800000012';
    await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp: '000000' } });
    expect(res.statusCode).toBe(401);
  });

  it('too many wrong attempts (>5) invalidates the OTP → 401', async () => {
    const phone = '9800000013';
    await sendAndGetOtp(phone, 'CUSTOMER');
    for (let i = 0; i < 5; i++) {
      await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp: '000000' } });
    }
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp: '000000' } });
    expect(res.statusCode).toBe(401);
  });

  it('no OTP sent → 401', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone: '9800000014', role: 'CUSTOMER', otp: '123456' } });
    expect(res.statusCode).toBe(401);
  });
});
