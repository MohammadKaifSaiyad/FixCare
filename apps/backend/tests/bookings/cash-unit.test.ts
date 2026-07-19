import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { flushTestRedis } from '../helpers/redis.js';
import { redis } from '../../src/shared/redis/client.js';
import { mintCashReceiptCode, verifyCashReceiptCode, type CashReceiptPayload } from '../../src/modules/bookings/cash.js';

// No app, no injects — unit coverage of the payload boundary in verifyCashReceiptCode.

afterAll(() => redis.quit());
beforeEach(async () => { await flushTestRedis(); });

async function mintAndVerify(payload: unknown) {
  const r = await mintCashReceiptCode('b-unit', payload as CashReceiptPayload);
  if (r.status !== 'ok') throw new Error('mint throttled in unit test');
  return verifyCashReceiptCode('b-unit', r.code);
}

describe('verifyCashReceiptCode payload boundary', () => {
  it('accepts a well-formed positive-integer payload', async () => {
    const v = await mintAndVerify({ paymentId: 'p1', amountPaise: 45100 });
    expect(v).toEqual({ status: 'ok', payload: { paymentId: 'p1', amountPaise: 45100 } });
  });

  it('rejects zero, negative, and float amounts as invalid — a bad amount must never reach the debt increment', async () => {
    for (const amountPaise of [0, -45100, 451.5]) {
      const v = await mintAndVerify({ paymentId: 'p1', amountPaise });
      expect(v).toEqual({ status: 'invalid' });
    }
  });

  it('rejects a payload missing paymentId', async () => {
    expect(await mintAndVerify({ amountPaise: 45100 })).toEqual({ status: 'invalid' });
  });
});
