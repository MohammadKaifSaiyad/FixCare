import { describe, expect, it, beforeEach } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { makeTechnician } from '../bookings/helpers.js';

beforeEach(async () => { await resetDb(); });

describe('settlement schema', () => {
  it('LedgerEntry round-trips; the CHECK constraint rejects a negative cashDebtPaise', async () => {
    const t = await makeTechnician(['AC']);
    const e = await prisma.ledgerEntry.create({ data: { technicianId: t.technicianId, type: 'EARNING_CREDIT', amountPaise: 48000, metadata: { rateBps: 2000, basePaise: 60000 } } });
    expect(e.bookingId).toBeNull();
    await expect(
      prisma.$executeRawUnsafe(`UPDATE "Technician" SET "cashDebtPaise" = -1 WHERE id = '${t.technicianId}'`),
    ).rejects.toThrow(/Technician_cashDebtPaise_nonnegative|check constraint/i);
  });
});
