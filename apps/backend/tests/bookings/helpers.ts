import type { ServiceSkill } from '@prisma/client';
import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';

let seq = 0;
function uniquePhone(): string { return '9' + String(300000000 + seq++); }

export async function makeCustomer(): Promise<{ token: string; userId: string; customerId: string }> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  const c = await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return { token: signAccessToken(user.id, 'CUSTOMER'), userId: user.id, customerId: c.id };
}

export async function makeAdminToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({ data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: 'MANAGER' } });
  return signAccessToken(user.id, 'ADMIN');
}

let fixtureSeq = 0;

/** Seed a serviceable happy-path: zone+visitFee, a service priced in that zone, a pincode→zone
 *  mapping, and an address (owned by customerId) in that pincode. Unique per call (zone name +
 *  6-digit pincode), so it can be called more than once in a single test (e.g. two customers). */
export async function seedBookable(customerId: string, opts?: { visitFeePaise?: number; laborPaise?: number }) {
  const visitFeePaise = opts?.visitFeePaise ?? 14900;
  const laborPaise = opts?.laborPaise ?? 60000;
  const n = fixtureSeq++;
  const zoneName = `Zone-${n}`;
  const pincode = String(390001 + n); // 6-digit, unique per call
  const zone = await prisma.zone.create({ data: { name: zoneName, visitFeePaise } });
  const cat = await prisma.serviceCategory.create({ data: { name: `Cat-${n}` } });
  const service = await prisma.service.create({ data: { categoryId: cat.id, name: 'AC gas refill', tier: 'T2', requiredSkill: 'AC' } });
  await prisma.servicePrice.create({ data: { serviceId: service.id, zoneId: zone.id, laborPaise } });
  await prisma.pincodeZone.create({ data: { pincode, zoneId: zone.id } });
  const address = await prisma.address.create({
    data: { customerId, label: 'Home', line1: '12 MG Road', pincode, zoneId: zone.id, isDefault: true },
  });
  return { zone, cat, service, address, visitFeePaise, laborPaise, zoneName, pincode };
}

export async function makeTechnician(skills: ServiceSkill[] = ['AC'], status: 'VERIFIED' | 'PENDING' = 'VERIFIED') {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'TECHNICIAN' } });
  const t = await prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills, status } });
  return { token: signAccessToken(user.id, 'TECHNICIAN'), userId: user.id, technicianId: t.id };
}

/** Seed an ACTIVE DiagnosedIssue in the given category. */
export async function seedIssue(categoryId: string, name = 'Compressor fault') {
  return prisma.diagnosedIssue.create({ data: { name, categoryId } });
}

/** B4b: diagnosis requires both photo slots. Seed them directly (the photo ENDPOINTS have their own
 *  tests in tests/technician-jobs/photos.test.ts — fixtures shortcut through prisma for speed). */
export async function seedDiagnosisPhotos(bookingId: string) {
  for (const kind of ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP'] as const) {
    await prisma.photoEvidence.create({
      data: { bookingId, kind, r2Key: `jobs/${bookingId}/${kind}-seed.jpg`, capturedAt: new Date() },
    });
  }
}
