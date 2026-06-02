import { describe, expect, it } from 'vitest';
import { hashPassword, verifyPassword } from '../../src/shared/auth/argon2.js';

describe('argon2 password helpers', () => {
  it('hashes then verifies the correct password', async () => {
    const hash = await hashPassword('s3cret-password');
    expect(hash).not.toBe('s3cret-password');
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(await verifyPassword(hash, 's3cret-password')).toBe(true);
  });

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('s3cret-password');
    expect(await verifyPassword(hash, 'wrong')).toBe(false);
  });
});
