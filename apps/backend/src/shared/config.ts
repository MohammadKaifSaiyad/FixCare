import { z } from 'zod';

const ConfigSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.url(),
  REDIS_URL: z.url(),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  REFRESH_TTL_DAYS: z.coerce.number().int().positive().default(30),
  OTP_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  OTP_MAX_SENDS_PER_WINDOW: z.coerce.number().int().positive().default(3),
  OTP_SEND_WINDOW_SECONDS: z.coerce.number().int().positive().default(900),
  OTP_MAX_VERIFY_ATTEMPTS: z.coerce.number().int().positive().default(5),
});

export type Config = z.infer<typeof ConfigSchema>;

/** Parse + validate an env-like object. Throws a readable error if invalid. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const result = ConfigSchema.safeParse(env);
  if (!result.success) {
    const issues = result.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid configuration: ${issues}`);
  }
  return result.data;
}

/** The validated, app-wide config. Importing this fails fast at boot if env is invalid. */
export const config = loadConfig();
