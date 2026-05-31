import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    fileParallelism: false,
    env: { DATABASE_URL: process.env.TEST_DATABASE_URL ?? '' },
  },
});
