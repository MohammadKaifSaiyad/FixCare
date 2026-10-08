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
    const e = await prisma.ledgerEntry.create({ data: { technicianId: t.id, type: 'PAYOUT', amountPaise: 100 } });
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: e.id } });
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: e.id } }))
      .rejects.toMatchObject({ code: 'P2002' });
  });

  it('a payoutEntryId matching no ledger entry is rejected (FK)', async () => {
    const t = await tech();
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: 'missing' } }))
      .rejects.toMatchObject({ code: 'P2003' });
  });

  it('the DB rejects a second REQUESTED row for one technician (partial unique index); a closed one is allowed', async () => {
    const t = await tech();
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 25000 } });
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 30000 } })).rejects.toMatchObject({ code: 'P2002' });
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 30000, status: 'REJECTED' } });
  });

  it('the DB rejects a zero or negative amount (CHECK)', async () => {
    const t = await tech();
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 0 } })).rejects.toThrow();
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: -5 } })).rejects.toThrow();
  });

  it('a transfer reference is unique across requests (many NULLs allowed)', async () => {
    const t = await tech();
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, status: 'REJECTED' } });
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, status: 'REJECTED' } });
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, status: 'PAID', transferReference: 'UTR-1' } });
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, status: 'PAID', transferReference: 'UTR-1' } }))
      .rejects.toMatchObject({ code: 'P2002' });
  });

  it('PAYOUT_MIN_PAISE defaults to ₹100', () => {
    expect(config.PAYOUT_MIN_PAISE).toBe(10000);
  });
});
