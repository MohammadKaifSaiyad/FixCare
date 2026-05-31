import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    fileParallelism: false,
    include: ['tests/**/*.test.ts'],
    globalTeardown: './tests/teardown.ts',
    env: { DATABASE_URL: process.env.TEST_DATABASE_URL ?? '' },
  },
});
