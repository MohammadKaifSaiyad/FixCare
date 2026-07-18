import { describe, expect, it } from 'vitest';
import { DevPaymentGateway, RazorpayGateway, paymentGateway } from '../../src/shared/third-party/razorpay.js';

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

  it('the module singleton is the Dev impl outside production', () => {
    expect(paymentGateway).toBeInstanceOf(DevPaymentGateway);
  });
});

describe('RazorpayGateway boot safety', () => {
  it('constructs WITHOUT creds; first USE fails with a clear config error (lazy, R2 posture)', async () => {
    const g = new RazorpayGateway();
    await expect(g.createOrder(100, 'x')).rejects.toThrow(/Razorpay is not configured/);
    expect(() => g.verifyWebhookSignature('{}', 'sig')).toThrow(/Razorpay is not configured/);
  });
});
