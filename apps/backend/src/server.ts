import { buildApp } from './app.js';
import { config } from './shared/config.js';

const app = await buildApp();
app
  .listen({ port: config.PORT, host: '0.0.0.0' })
  .then((addr) => console.log(`FixCare API listening on ${addr}`))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
