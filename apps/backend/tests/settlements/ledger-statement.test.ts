import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer } from '../bookings/helpers.js';
import { assignedBooking, auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const page = (token: string, qs = '') => app.inject({ method: 'GET', url: `/technician/me/ledger${qs}`, headers: auth(token) });

describe('GET /technician/me/ledger', () => {
  it('newest first; booking number + service on job rows only; own rows only', async () => {
    const t = await makeTechnician(['AC']);
    const other = await makeTechnician(['AC']);
    const b = await assignedBooking(app, t.technicianId, 'CLOSED');
    await ledger(t.technicianId, [
      { type: 'EARNING_CREDIT', amountPaise: 48000, bookingId: b.bookingId, createdAt: new Date('2026-10-01T00:00:00Z'), metadata: { rateBps: 2000, basePaise: 60000 } },
      { type: 'PAYOUT', amountPaise: 48000, createdAt: new Date('2026-10-02T00:00:00Z') },
    ]);
    await ledger(other.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 1 }]);
    const res = await page(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      entries: [
        { id: expect.any(String), type: 'PAYOUT', amountPaise: 48000, bookingNumber: null, serviceName: null, rateBps: null, createdAt: '2026-10-02T00:00:00.000Z' },
        { id: expect.any(String), type: 'EARNING_CREDIT', amountPaise: 48000, bookingNumber: b.bookingNumber, serviceName: b.serviceName, rateBps: 2000, createdAt: '2026-10-01T00:00:00.000Z' },
      ],
      nextCursor: null,
    });
  });

  it('rateBps comes from the row metadata only when it is an integer', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [
      { type: 'COMMISSION', amountPaise: 9000, metadata: { rateBps: 1500, basePaise: 60000 }, createdAt: new Date('2026-10-01T00:00:00Z') },
      { type: 'COMMISSION', amountPaise: 1, metadata: { rateBps: '1500' }, createdAt: new Date('2026-10-02T00:00:00Z') },
      { type: 'COMMISSION', amountPaise: 2, metadata: { rateBps: 12.5 }, createdAt: new Date('2026-10-03T00:00:00Z') },
      { type: 'COMMISSION', amountPaise: 3, createdAt: new Date('2026-10-04T00:00:00Z') },
    ]);
    const rates = ((await page(t.token)).json() as { entries: Array<{ rateBps: number | null }> }).entries.map((e) => e.rateBps);
    expect(rates).toEqual([null, null, null, 1500]);
  });

  it('pages through rows with identical timestamps without repeating or skipping', async () => {
    const t = await makeTechnician(['AC']);
    const same = new Date('2026-10-03T10:00:00Z');
    await ledger(t.technicianId, Array.from({ length: 5 }, (_, i) => ({ type: 'EARNING_CREDIT' as const, amountPaise: 100 + i, createdAt: same })));
    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const qs: string = `?limit=2${cursor ? `&before=${encodeURIComponent(cursor)}` : ''}`;
      const body = (await page(t.token, qs)).json() as { entries: { id: string }[]; nextCursor: string | null };
      seen.push(...body.entries.map((e) => e.id));
      cursor = body.nextCursor;
    } while (cursor);
    expect(seen).toHaveLength(5);
    expect(new Set(seen).size).toBe(5);
  });

  it('400 for a bad limit or cursor; 403 for a customer', async () => {
    const t = await makeTechnician(['AC']);
    const junk = [
      '?limit=0', '?limit=51', '?limit=abc', '?before=not-a-cursor', '?x=1',
      `?before=${Buffer.from('2026-10-01T00:00:00.000Z|nope').toString('base64url')}`,
      `?before=${Buffer.from('garbage|00000000-0000-4000-8000-000000000000').toString('base64url')}`,
      '?before=%FF%FE',
    ];
    for (const qs of junk) {
      expect((await page(t.token, qs)).statusCode).toBe(400);
    }
    const c = await makeCustomer();
    expect((await page(c.token)).statusCode).toBe(403);
  });
});
