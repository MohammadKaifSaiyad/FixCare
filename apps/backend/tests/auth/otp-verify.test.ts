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

  it('existing user logs in as STORED role (ignores role hint) + audits USER_LOGGED_IN', async () => {
    const phone = '9800000011';
    let otp = await sendAndGetOtp(phone, 'CUSTOMER');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.role).toBe('CUSTOMER');
    const user = await prisma.user.findUnique({ where: { phone }, include: { customer: true, technician: true } });
    expect(user?.customer).toBeTruthy();
    expect(user?.technician).toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'USER_LOGGED_IN', actorId: user!.id } });
    expect(audit).toBeTruthy();
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
