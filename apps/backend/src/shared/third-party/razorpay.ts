import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
import Razorpay from 'razorpay';
import { config } from '../config.js';

/** Abstraction over the payment gateway. The rest of the code depends on this, not the SDK. */
export interface PaymentGateway {
  /** Create a gateway order for exactly amountPaise (INR). `receipt` carries the bookingId. */
  createOrder(amountPaise: number, receipt: string): Promise<{ orderId: string }>;
  /** HMAC-SHA256 of the RAW request body with the webhook secret; timing-safe compare. */
  verifyWebhookSignature(rawBody: string, signature: string): boolean;
  /** Refund a captured payment (full or partial), amountPaise. Returns the gateway refund id. */
  refund(paymentId: string, amountPaise: number): Promise<{ refundId: string }>;
}

const DEV_WEBHOOK_SECRET = 'dev-webhook-secret';

function hmacHex(secret: string, rawBody: string): string {
  return createHmac('sha256', secret).update(rawBody).digest('hex');
}

function safeCompareHex(expected: string, given: string): boolean {
  // Decode as HEX (not utf8): compares the 32 digest bytes, so signature casing can never matter.
  // Invalid/odd-length hex decodes short → length mismatch → false (fail closed).
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(given, 'hex');
  if (a.length === 0 || a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Dev/test gateway: no network. `signPayload` lets tests produce VALID webhook signatures. */
export class DevPaymentGateway implements PaymentGateway {
  async createOrder(_amountPaise: number, _receipt: string): Promise<{ orderId: string }> {
    return { orderId: `order_dev_${randomUUID().slice(0, 12)}` };
  }
  verifyWebhookSignature(rawBody: string, signature: string): boolean {
    return safeCompareHex(hmacHex(DEV_WEBHOOK_SECRET, rawBody), signature);
  }
  async refund(_paymentId: string, _amountPaise: number): Promise<{ refundId: string }> {
    return { refundId: `rfnd_dev_${randomUUID().slice(0, 12)}` };
  }
  /** Test hook: sign a payload the way the gateway would. */
  signPayload(rawBody: string): string {
    return hmacHex(DEV_WEBHOOK_SECRET, rawBody);
  }
}

/** Real Razorpay. Creds checked LAZILY on first use — production must boot before KYC
 *  approval provisions the keys (same posture as R2PhotoStorage). */
export class RazorpayGateway implements PaymentGateway {
  private lazy: { client: Razorpay; webhookSecret: string } | null = null;
  private rz(): { client: Razorpay; webhookSecret: string } {
    if (this.lazy) return this.lazy;
    if (!config.RAZORPAY_KEY_ID || !config.RAZORPAY_KEY_SECRET || !config.RAZORPAY_WEBHOOK_SECRET) {
      throw new Error('Razorpay is not configured (RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET/RAZORPAY_WEBHOOK_SECRET)');
    }
    this.lazy = {
      client: new Razorpay({ key_id: config.RAZORPAY_KEY_ID, key_secret: config.RAZORPAY_KEY_SECRET }),
      webhookSecret: config.RAZORPAY_WEBHOOK_SECRET,
    };
    return this.lazy;
  }
  async createOrder(amountPaise: number, receipt: string): Promise<{ orderId: string }> {
    const { client } = this.rz();
    try {
      const order = await client.orders.create({ amount: amountPaise, currency: 'INR', receipt });
      return { orderId: order.id };
    } catch {
      throw new Error('Razorpay createOrder failed'); // typed boundary: never leak raw SDK errors
    }
  }
  verifyWebhookSignature(rawBody: string, signature: string): boolean {
    const { webhookSecret } = this.rz();
    return safeCompareHex(hmacHex(webhookSecret, rawBody), signature);
  }
  async refund(paymentId: string, amountPaise: number): Promise<{ refundId: string }> {
    const { client } = this.rz();
    try {
      const r = await client.payments.refund(paymentId, { amount: amountPaise });
      return { refundId: r.id };
    } catch {
      throw new Error('Razorpay refund failed'); // typed boundary: never leak raw SDK errors
    }
  }
}

/** Factory: dev stub everywhere except production (same posture as makeOtpSender/makePhotoStorage). */
export function makePaymentGateway(): PaymentGateway {
  return config.NODE_ENV === 'production' ? new RazorpayGateway() : new DevPaymentGateway();
}

/** Module singleton — services import this; tests reach the Dev impl through it. */
export const paymentGateway: PaymentGateway = makePaymentGateway();
