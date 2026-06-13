/** Mask all but the last 4 digits of a phone-like string with • (no PII leak — Golden Rule 7). */
export function maskPhone(phone: string): string {
  if (phone.length <= 4) return '•'.repeat(phone.length);
  return '•'.repeat(phone.length - 4) + phone.slice(-4);
}
