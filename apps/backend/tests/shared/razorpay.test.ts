import { describe, expect, it, vi, afterEach } from 'vitest';
import { DevPaymentGateway, RazorpayGateway, paymentGateway, makePaymentGateway } from '../../src/shared/third-party/razorpay.js';
import { config } from '../../src/shared/config.js';

describe('DevPaymentGateway', () => {
  it('creates deterministic dev order ids', async () => {
    const g = new DevPaymentGateway();
    const a = await g.createOrder(45100, 'booking-1');
    const b = await g.createOrder(45100, 'booking-1');
    expect(a.orderId).toMatch(/^order_dev_/);
    expect(a.orderId).not.toBe(b.orderId); // each call is a NEW order
  });

  it('signPayload produces a signature that verifyWebhookSignature accepts; tampering rejects', () => {
    const g = new DevPaymentGateway();
    const body = JSON.stringify({ event: 'payment.captured' });
    const sig = g.signPayload(body);
    expect(g.verifyWebhookSignature(body, sig)).toBe(true);
    expect(g.verifyWebhookSignature(body + 'x', sig)).toBe(false);
    expect(g.verifyWebhookSignature(body, 'deadbeef')).toBe(false);
  });

  it('the module singleton is the Dev impl when Razorpay is unconfigured (test env has no keys)', () => {
    expect(paymentGateway).toBeInstanceOf(DevPaymentGateway);
  });
});

describe('makePaymentGateway selection rule', () => {
  afterEach(() => vi.restoreAllMocks());

  it('unconfigured (no keys), non-production → Dev stub (offline tests / keyless boot)', () => {
    vi.spyOn(config, 'NODE_ENV', 'get').mockReturnValue('development');
    vi.spyOn(config, 'RAZORPAY_KEY_ID', 'get').mockReturnValue(undefined);
    expect(makePaymentGateway()).toBeInstanceOf(DevPaymentGateway);
  });

  it('all three keys present (test OR live keys) → real RazorpayGateway even outside production', () => {
    vi.spyOn(config, 'NODE_ENV', 'get').mockReturnValue('development');
    vi.spyOn(config, 'RAZORPAY_KEY_ID', 'get').mockReturnValue('rzp_test_x');
    vi.spyOn(config, 'RAZORPAY_KEY_SECRET', 'get').mockReturnValue('secret');
    vi.spyOn(config, 'RAZORPAY_WEBHOOK_SECRET', 'get').mockReturnValue('whsec');
    expect(makePaymentGateway()).toBeInstanceOf(RazorpayGateway);
  });

  it('production always → real RazorpayGateway (even before keys are provisioned)', () => {
    vi.spyOn(config, 'NODE_ENV', 'get').mockReturnValue('production');
    vi.spyOn(config, 'RAZORPAY_KEY_ID', 'get').mockReturnValue(undefined);
    expect(makePaymentGateway()).toBeInstanceOf(RazorpayGateway);
  });

  it('partial keys (id but no secret), non-production → Dev stub (fail safe, no half-real)', () => {
    vi.spyOn(config, 'NODE_ENV', 'get').mockReturnValue('development');
    vi.spyOn(config, 'RAZORPAY_KEY_ID', 'get').mockReturnValue('rzp_test_x');
    vi.spyOn(config, 'RAZORPAY_KEY_SECRET', 'get').mockReturnValue(undefined);
    vi.spyOn(config, 'RAZORPAY_WEBHOOK_SECRET', 'get').mockReturnValue(undefined);
    expect(makePaymentGateway()).toBeInstanceOf(DevPaymentGateway);
  });
});

describe('RazorpayGateway boot safety', () => {
  afterEach(() => vi.restoreAllMocks());

  it('constructs WITHOUT creds; first USE fails with a clear config error (lazy, R2 posture)', async () => {
    // Deterministic regardless of the ambient .env: force the unconfigured case, since a
    // developer running with real Razorpay keys in .env would otherwise create a live order here.
    // NOTE: vitest.config.ts already forces RAZORPAY_* empty for the whole suite; this local
    // mock is belt-and-suspenders so THIS test stays correct even if that block is ever changed.
    vi.spyOn(config, 'RAZORPAY_KEY_ID', 'get').mockReturnValue(undefined);
    vi.spyOn(config, 'RAZORPAY_KEY_SECRET', 'get').mockReturnValue(undefined);
    vi.spyOn(config, 'RAZORPAY_WEBHOOK_SECRET', 'get').mockReturnValue(undefined);
    const g = new RazorpayGateway();
    await expect(g.createOrder(100, 'x')).rejects.toThrow(/Razorpay is not configured/);
    expect(() => g.verifyWebhookSignature('{}', 'sig')).toThrow(/Razorpay is not configured/);
  });
});
