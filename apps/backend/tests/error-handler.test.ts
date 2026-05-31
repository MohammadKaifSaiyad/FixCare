import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { ForbiddenError } from '../src/shared/errors.js';

const app = await buildApp();
app.get('/__boom', async () => { throw new ForbiddenError('nope'); });
app.get('/__crash', async () => { throw new Error('secret internal detail'); });
afterAll(() => app.close());

describe('global error handler', () => {
  it('maps a typed AppError to its status + safe body', async () => {
    const res = await app.inject({ method: 'GET', url: '/__boom' });
    expect(res.statusCode).toBe(403);
    const body = res.json();
    expect(body.code).toBe('FORBIDDEN');
    expect(body.message).toBe('nope');
    expect(body.stack).toBeUndefined();
  });

  it('maps an unexpected error to a generic 500 without leaking detail', async () => {
    const res = await app.inject({ method: 'GET', url: '/__crash' });
    expect(res.statusCode).toBe(500);
    const body = res.json();
    expect(body.message).not.toContain('secret internal detail');
  });
});
