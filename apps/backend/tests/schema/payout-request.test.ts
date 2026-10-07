import { beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';
import { config } from '../../src/shared/config.js';

async function tech() {
  const user = await prisma.user.create({ data: { phone: '9811100002', role: 'TECHNICIAN' } });
  return prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills: ['AC'] } });
}

describe('PayoutRequest model', () => {
  beforeEach(resetDb);

  it('defaults to REQUESTED with no review fields', async () => {
    const t = await tech();
    const r = await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 25000 } });
    expect(r.status).toBe('REQUESTED');
    expect(r.reviewNote).toBeNull();
    expect(r.reviewedAt).toBeNull();
    expect(r.payoutEntryId).toBeNull();
  });

  it('a ledger entry backs at most one request (payoutEntryId is unique)', async () => {
    const t = await tech();
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: 'e1' } });
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: 'e1' } }))
      .rejects.toMatchObject({ code: 'P2002' });
  });

  it('PAYOUT_MIN_PAISE defaults to ₹100', () => {
    expect(config.PAYOUT_MIN_PAISE).toBe(10000);
  });
});
