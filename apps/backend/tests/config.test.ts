import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/shared/config.js';

const base = {
  NODE_ENV: 'test',
  PORT: '3000',
  DATABASE_URL: 'postgresql://fixcare:fixcare_dev@localhost:5432/fixcare_test?schema=public',
  REDIS_URL: 'redis://localhost:6379',
  JWT_SECRET: 'x'.repeat(32),
};

describe('config', () => {
  it('parses a valid environment', () => {
    const c = loadConfig(base);
    expect(c.PORT).toBe(3000); // coerced to number
    expect(c.JWT_SECRET).toHaveLength(32);
  });

  it('throws when JWT_SECRET is missing', () => {
    const { JWT_SECRET, ...without } = base;
    expect(() => loadConfig(without)).toThrow(/JWT_SECRET/);
  });

  it('throws when JWT_SECRET is too short', () => {
    expect(() => loadConfig({ ...base, JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/);
  });
});
