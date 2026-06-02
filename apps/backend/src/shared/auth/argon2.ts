import argon2 from 'argon2';

/** Hash a plaintext password with argon2id. */
export function hashPassword(plain: string): Promise<string> {
  return argon2.hash(plain, { type: argon2.argon2id });
}

/** Verify a plaintext password against an argon2id hash. Returns false on mismatch (never throws for a bad password). */
export async function verifyPassword(hash: string, plain: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain);
  } catch {
    return false;
  }
}
