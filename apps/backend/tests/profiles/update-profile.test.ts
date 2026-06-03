import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { registerAndToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

function auth(token: string) { return { authorization: `Bearer ${token}` }; }

describe('PATCH /me/profile', () => {
  it('updates a customer name', async () => {
    const { token, userId } = await registerAndToken(app, '9800000080', 'CUSTOMER');
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { name: 'Asha' } });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe('Asha');
    const row = await prisma.customer.findUnique({ where: { userId } });
    expect(row!.name).toBe('Asha');
  });

  it('updates a technician name + full-replaces skills', async () => {
    const { token, userId } = await registerAndToken(app, '9800000081', 'TECHNICIAN');
    await prisma.technician.update({ where: { userId }, data: { skills: ['AC', 'FAN'] } });
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { name: 'Ramesh', skills: ['ELECTRICAL'] } });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe('Ramesh');
    expect(res.json().skills).toEqual(['ELECTRICAL']);
  });

  it('partial PATCH (skills only) leaves name unchanged', async () => {
    const { token, userId } = await registerAndToken(app, '9800000082', 'TECHNICIAN');
    await prisma.technician.update({ where: { userId }, data: { name: 'Keep', skills: ['AC'] } });
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { skills: ['WIRING'] } });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe('Keep');
    expect(res.json().skills).toEqual(['WIRING']);
  });

  it('empty body → 400', async () => {
    const { token } = await registerAndToken(app, '9800000083', 'CUSTOMER');
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: {} });
    expect(res.statusCode).toBe(400);
  });

  it('unknown/forbidden field (status) → 400', async () => {
    const { token } = await registerAndToken(app, '9800000084', 'CUSTOMER');
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { status: 'SUSPENDED' } });
    expect(res.statusCode).toBe(400);
  });

  it('writes a PROFILE_UPDATED audit with field NAMES (not values)', async () => {
    const { token, userId } = await registerAndToken(app, '9800000085', 'CUSTOMER');
    await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { name: 'Secret Name' } });
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PROFILE_UPDATED', actorId: userId } });
    expect(audit).toBeTruthy();
    expect(audit!.actorType).toBe('USER');
    const meta = audit!.metadata as { fields: string[] };
    expect(meta.fields).toContain('name');
    expect(JSON.stringify(meta)).not.toContain('Secret Name');
  });
});
