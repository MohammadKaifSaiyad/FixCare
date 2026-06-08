import { randomInt } from 'node:crypto';

// Crockford base32 alphabet (no I, L, O, U — avoids ambiguity when read aloud to support).
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** Generate a human-friendly booking reference, e.g. "FC-7K3M2Q".
 *  6 chars of crypto-random base32; uniqueness is enforced by the DB @unique constraint,
 *  the caller retries on the rare P2002 collision. */
export function generateBookingNumber(): string {
  let code = '';
  for (let i = 0; i < 6; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return `FC-${code}`;
}
