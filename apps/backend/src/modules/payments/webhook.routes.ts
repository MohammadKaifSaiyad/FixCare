import type { FastifyInstance } from 'fastify';
import { handleWebhookEvent } from './webhook.service.js';

/** Gateway webhooks. NO requireAuth — the HMAC signature over the RAW body is the auth.
 *  The raw string must be preserved byte-for-byte for the HMAC, so this plugin scope
 *  re-registers the JSON parser to keep the raw body instead of parsing it. */
export async function registerWebhookRoutes(app: FastifyInstance) {
  await app.register(async (scope) => {
    scope.removeContentTypeParser('application/json');
    scope.addContentTypeParser('application/json', { parseAs: 'string' }, (_req, body, done) => {
      done(null, body); // hand the raw string through as req.body
    });
    // The global rate limiter must NOT gate gateway deliveries: a traffic burst sharing the
    // 100/min budget would 429 Razorpay's webhooks into a retry storm. The HMAC signature is
    // this route's gate — an attacker without the secret gets 401s at one HMAC each. If junk
    // floods ever matter, the backstop belongs at the Caddy reverse proxy (IP/conn throttle),
    // not app-level rate limiting.
    scope.post('/webhooks/razorpay', { config: { rateLimit: false } }, async (req, reply) => {
      await handleWebhookEvent(req.body as string, req.headers['x-razorpay-signature'] as string | undefined);
      return reply.send({ received: true });
    });
  });
}
