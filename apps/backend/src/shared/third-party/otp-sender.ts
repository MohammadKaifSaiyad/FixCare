import { config } from '../config.js';

/** Abstraction over OTP delivery. The rest of the code depends on this, not a vendor SDK. */
export interface OtpSender {
  send(phone: string, otp: string): Promise<void>;
}

/** Dev/test sender: logs the OTP. Never used in production. */
export class DevOtpSender implements OtpSender {
  async send(phone: string, otp: string): Promise<void> {
    console.log(`[DevOtpSender] OTP for ...${phone.slice(-4)} = ${otp}`);
  }
}

/** Real MSG91 sender — INERT until DLT/template approval. Throws if used. */
export class Msg91OtpSender implements OtpSender {
  async send(_phone: string, _otp: string): Promise<void> {
    throw new Error('Msg91OtpSender is not enabled yet (pending DLT/template approval)');
  }
}

/** Factory: dev stub everywhere except production. */
export function makeOtpSender(): OtpSender {
  return config.NODE_ENV === 'production' ? new Msg91OtpSender() : new DevOtpSender();
}
