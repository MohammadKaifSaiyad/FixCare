import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { resolvePincode } from '../../src/modules/addresses/serviceability.service.js';
import { seedZoneWithPincode } from './helpers.js';
import { buildApp } from '../../src/app.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomerToken } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

describe('resolvePincode', () => {
  it('maps a known pincode to its active zone', async () => {
    const zone = await seedZoneWithPincode('Vadodara', 14900, '390001');
    const res = await resolvePincode('390001');
    expect(res.serviceable).toBe(true);
    expect(res.zone).toMatchObject({ id: zone.id, name: 'Vadodara', visitFeePaise: 14900 });
  });

  it('unknown pincode → unserviceable with message', async () => {
    const res = await resolvePincode('395003');
    expect(res.serviceable).toBe(false);
    expect(res.zone).toBeNull();
    expect(res.message).toBe("We don't serve this area yet");
  });

  it('pincode mapped to a soft-deleted zone → unserviceable', async () => {
    const zone = await seedZoneWithPincode('Gone', 100, '390002');
    await prisma.zone.update({ where: { id: zone.id }, data: { deletedAt: new Date() } });
    const res = await resolvePincode('390002');
    expect(res.serviceable).toBe(false);
    expect(res.zone).toBeNull();
  });

  it('pincode mapped to an INACTIVE zone → unserviceable', async () => {
    const zone = await seedZoneWithPincode('Off', 100, '390003');
    await prisma.zone.update({ where: { id: zone.id }, data: { status: 'INACTIVE' } });
    expect((await resolvePincode('390003')).serviceable).toBe(false);
  });

  it('a soft-deleted/INACTIVE pincode mapping → unserviceable even if the zone is active', async () => {
    const zone = await seedZoneWithPincode('Vadodara', 14900, '390004');
    await prisma.pincodeZone.updateMany({ where: { pincode: '390004' }, data: { status: 'INACTIVE' } });
    expect((await resolvePincode('390004')).serviceable).toBe(false);
    await prisma.pincodeZone.updateMany({ where: { pincode: '390004' }, data: { status: 'ACTIVE', deletedAt: new Date() } });
    expect((await resolvePincode('390004')).serviceable).toBe(false);
    void zone;
  });
});

const app = await buildApp();
afterAll(() => app.close());
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('GET /serviceability', () => {
  beforeEach(async () => { await resetDb(); await flushTestRedis(); });

  it('known pincode → 200 serviceable with zone', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'GET', url: '/serviceability?pincode=390001', headers: auth(tok) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ serviceable: true, zone: { name: 'Vadodara', visitFeePaise: 14900 } });
  });

  it('unknown pincode → 200 unserviceable with message', async () => {
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'GET', url: '/serviceability?pincode=395003', headers: auth(tok) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ serviceable: false, zone: null, message: "We don't serve this area yet" });
  });

  it('non-6-digit pincode → 400', async () => {
    const tok = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: '/serviceability?pincode=39', headers: auth(tok) })).statusCode).toBe(400);
    expect((await app.inject({ method: 'GET', url: '/serviceability?pincode=abcdef', headers: auth(tok) })).statusCode).toBe(400);
  });

  it('no token → 401', async () => {
    expect((await app.inject({ method: 'GET', url: '/serviceability?pincode=390001' })).statusCode).toBe(401);
  });
});
