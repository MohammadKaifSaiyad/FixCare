import { buildApp } from './app.js';
import { config } from './shared/config.js';
import { startSettlementSweep } from './shared/queue/settlement-sweep.js';

const app = await buildApp();
const stopSweep = await startSettlementSweep();

const shutdown = async () => {
  await stopSweep();
  await app.close();
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

app
  .listen({ port: config.PORT, host: '0.0.0.0' })
  .then((addr) => console.log(`FixCare API listening on ${addr}`))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
