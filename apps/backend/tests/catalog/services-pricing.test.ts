import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

async function seedBase(mgr: string) {
  const vad = (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } })).json();
  const pad = (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Padra', visitFeePaise: 9900 } })).json();
  const cat = (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).json();
  const svc = (await app.inject({ method: 'POST', url: '/catalog/services', headers: auth(mgr), payload: { categoryId: cat.id, name: 'AC gas refill', tier: 'T2' } })).json();
  return { vad, pad, cat, svc };
}

describe('services + geofenced pricing', () => {
  it('geofencing: same service has different labor price per zone; visit fee from the zone', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, pad, svc } = await seedBase(mgr);
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(mgr), payload: { laborPaise: 60000 } });
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${pad.id}`, headers: auth(mgr), payload: { laborPaise: 50000 } });

    const cust = await makeCustomerToken();
    const inVad = (await app.inject({ method: 'GET', url: `/catalog/services?zoneId=${vad.id}`, headers: auth(cust) })).json();
    const inPad = (await app.inject({ method: 'GET', url: `/catalog/services?zoneId=${pad.id}`, headers: auth(cust) })).json();
    const vadSvc = inVad.find((s: { id: string }) => s.id === svc.id);
    const padSvc = inPad.find((s: { id: string }) => s.id === svc.id);
    expect(vadSvc.laborPaise).toBe(60000);
    expect(padSvc.laborPaise).toBe(50000);
    expect(vadSvc.visitFeePaise).toBe(14900);
    expect(padSvc.visitFeePaise).toBe(9900);
  });

  it('price upsert updates in place (no duplicate) + PRICE_CHANGED audit from→to', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, svc } = await seedBase(mgr);
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(mgr), payload: { laborPaise: 60000 } });
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(mgr), payload: { laborPaise: 65000 } });
    const rows = await prisma.servicePrice.findMany({ where: { serviceId: svc.id, zoneId: vad.id } });
    expect(rows).toHaveLength(1);
    expect(rows[0]!.laborPaise).toBe(65000);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED' }, orderBy: { createdAt: 'desc' } });
    const meta = audit!.metadata as { fromPaise: number; toPaise: number };
    expect(meta.fromPaise).toBe(60000);
    expect(meta.toPaise).toBe(65000);
  });

  it('SUPPORT cannot upsert a price (403)', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, svc } = await seedBase(mgr);
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(sup), payload: { laborPaise: 1 } })).statusCode).toBe(403);
  });

  it('unpriced-in-zone service has laborPaise null', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, svc } = await seedBase(mgr);
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/services?zoneId=${vad.id}`, headers: auth(cust) })).json();
    const found = list.find((s: { id: string }) => s.id === svc.id);
    expect(found.laborPaise).toBeNull();
  });
});
