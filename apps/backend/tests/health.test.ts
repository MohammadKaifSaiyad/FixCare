import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';

const app = await buildApp();
afterAll(() => app.close());

describe('GET /health', () => {
  it('returns 200 with db and redis reachable', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.status).toBe('ok');
    expect(body.db).toBe('up');
    expect(body.redis).toBe('up');
  });
});
