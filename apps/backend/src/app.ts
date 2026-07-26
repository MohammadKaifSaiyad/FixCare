import Fastify, { type FastifyInstance } from 'fastify';
import { registerSecurity } from './plugins/security.js';
import { registerErrorHandler } from './shared/middleware/errorHandler.js';
import { prisma } from './shared/database/prisma.js';
import { redis } from './shared/redis/client.js';
import { registerAuthRoutes } from './modules/auth/auth.routes.js';
import { registerProfileRoutes } from './modules/profiles/profiles.routes.js';
import { registerCatalogRoutes } from './modules/catalog/catalog.routes.js';
import { registerAddressesRoutes } from './modules/addresses/addresses.routes.js';
import { registerBookingRoutes } from './modules/bookings/bookings.routes.js';
import { registerTechnicianJobRoutes } from './modules/technician-jobs/technician-jobs.routes.js';
import { registerWebhookRoutes } from './modules/payments/webhook.routes.js';
import { registerSettlementRoutes } from './modules/settlements/settlements.routes.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });

  await registerSecurity(app);
  registerErrorHandler(app);

  await registerAuthRoutes(app);
  await registerProfileRoutes(app);
  await registerCatalogRoutes(app);
  await registerAddressesRoutes(app);
  await registerBookingRoutes(app);
  await registerTechnicianJobRoutes(app);
  await registerWebhookRoutes(app);
  await registerSettlementRoutes(app);

  app.get('/health', async () => {
    let db = 'down';
    let redisState = 'down';
    try { await prisma.$queryRaw`SELECT 1`; db = 'up'; } catch { /* stays down */ }
    try { const pong = await redis.ping(); redisState = pong === 'PONG' ? 'up' : 'down'; } catch { /* stays down */ }
    const status = db === 'up' && redisState === 'up' ? 'ok' : 'degraded';
    return { status, db, redis: redisState };
  });

  return app;
}
