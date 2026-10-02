import { beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

async function techAndZone() {
  const user = await prisma.user.create({ data: { phone: '9811100001', role: 'TECHNICIAN' } });
  const t = await prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills: ['AC'] } });
  const z = await prisma.zone.create({ data: { name: 'Padra', visitFeePaise: 9900 } });
  return { t, z };
}

describe('Technician onboarding schema', () => {
  beforeEach(resetDb);

  it('a new technician has no review fields set', async () => {
    const { t } = await techAndZone();
    expect(t.reviewNote).toBeNull();
    expect(t.submittedAt).toBeNull();
    expect(t.reviewedAt).toBeNull();
  });

  it('links a technician to a zone once (the composite key rejects a duplicate)', async () => {
    const { t, z } = await techAndZone();
    await prisma.technicianZone.create({ data: { technicianId: t.id, zoneId: z.id } });
    await expect(prisma.technicianZone.create({ data: { technicianId: t.id, zoneId: z.id } }))
      .rejects.toMatchObject({ code: 'P2002' });
    const withZones = await prisma.technician.findUniqueOrThrow({ where: { id: t.id }, include: { zones: true } });
    expect(withZones.zones.map((x) => x.zoneId)).toEqual([z.id]);
  });

  it('accepts the TECHNICIAN_STATUS_CHANGED audit action', async () => {
    const row = await prisma.auditLog.create({
      data: { action: 'TECHNICIAN_STATUS_CHANGED', actorType: 'ADMIN', actorId: 'a1', subjectId: 't1', metadata: { from: 'KYC_SUBMITTED', to: 'VERIFIED' } },
    });
    expect(row.action).toBe('TECHNICIAN_STATUS_CHANGED');
  });
});
