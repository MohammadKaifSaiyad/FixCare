import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    fileParallelism: false,
    include: ['tests/**/*.test.ts'],
    globalTeardown: './tests/teardown.ts',
    env: {
      DATABASE_URL: process.env.TEST_DATABASE_URL ?? '',
      // Tests must use the offline DevPaymentGateway, never real Razorpay. Since a developer's
      // .env may now carry real (test-mode) Razorpay keys — which the factory treats as "use the
      // real gateway" — force them empty here so the test suite is deterministic and offline
      // regardless of how the shell env is sourced.
      RAZORPAY_KEY_ID: '',
      RAZORPAY_KEY_SECRET: '',
      RAZORPAY_WEBHOOK_SECRET: '',
    },
  },
});
