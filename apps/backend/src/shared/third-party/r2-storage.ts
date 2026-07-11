import { S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config.js';

const UPLOAD_TTL_SECONDS = 24 * 3600; // 24h — infrastructure.md:186-205
const READ_TTL_SECONDS = 15 * 60; // 15-min signed customer reads (design decision 3)

/** Abstraction over photo object storage. The rest of the code depends on this, not the S3 SDK. */
export interface PhotoStorage {
  /** Presigned PUT: Content-Type pinned to image/jpeg and the exact byte length signed in (1MB cap). */
  presignUpload(key: string, contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }>;
  /** HEAD the object — evidence must exist in R2 before it is recorded (Golden Rule 1). */
  objectExists(key: string): Promise<boolean>;
  /** Short-lived signed GET for DTOs. Never expose raw keys or permanent URLs. */
  presignRead(key: string): Promise<string>;
}

/** Dev/test storage: in-memory, deterministic URLs, no network. `markUploaded` fakes the PUT. */
export class DevPhotoStorage implements PhotoStorage {
  private uploaded = new Set<string>();
  markUploaded(key: string): void {
    this.uploaded.add(key);
  }
  async presignUpload(key: string, _contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }> {
    return { url: `https://dev-r2.local/upload/${encodeURIComponent(key)}`, expiresAt: new Date(Date.now() + UPLOAD_TTL_SECONDS * 1000) };
  }
  async objectExists(key: string): Promise<boolean> {
    return this.uploaded.has(key);
  }
  async presignRead(key: string): Promise<string> {
    return `https://dev-r2.local/read/${encodeURIComponent(key)}`;
  }
}

/** Real R2 (S3-compatible). Throws a clear error if the R2 env keys are missing. */
export class R2PhotoStorage implements PhotoStorage {
  private readonly client: S3Client;
  private readonly bucket: string;
  constructor() {
    if (!config.R2_ACCOUNT_ID || !config.R2_ACCESS_KEY_ID || !config.R2_SECRET_ACCESS_KEY || !config.R2_BUCKET) {
      throw new Error('R2 storage is not configured (R2_ACCOUNT_ID/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY/R2_BUCKET)');
    }
    this.bucket = config.R2_BUCKET;
    this.client = new S3Client({
      region: 'auto',
      endpoint: `https://${config.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId: config.R2_ACCESS_KEY_ID, secretAccessKey: config.R2_SECRET_ACCESS_KEY },
    });
  }
  async presignUpload(key: string, contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }> {
    try {
      // ContentType + ContentLength become SIGNED headers: the PUT must match them exactly,
      // which is how the jpeg-only + 1MB policy is enforced cryptographically.
      const cmd = new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: 'image/jpeg', ContentLength: contentLengthBytes });
      const url = await getSignedUrl(this.client, cmd, { expiresIn: UPLOAD_TTL_SECONDS });
      return { url, expiresAt: new Date(Date.now() + UPLOAD_TTL_SECONDS * 1000) };
    } catch {
      throw new Error('R2 presignUpload failed'); // typed boundary: never leak raw SDK errors
    }
  }
  async objectExists(key: string): Promise<boolean> {
    try {
      await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return true;
    } catch (e) {
      // NotFound is the name today; the 404 status is the durable signal across SDK versions.
      // This gates Golden Rule 1 (evidence must exist) — be robust, and fail closed otherwise.
      if (e && typeof e === 'object') {
        const err = e as { name?: string; $metadata?: { httpStatusCode?: number } };
        if (err.name === 'NotFound' || err.$metadata?.httpStatusCode === 404) return false;
      }
      throw new Error('R2 objectExists failed'); // typed boundary: never leak raw SDK errors
    }
  }
  async presignRead(key: string): Promise<string> {
    try {
      return await getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: READ_TTL_SECONDS });
    } catch {
      throw new Error('R2 presignRead failed'); // typed boundary: never leak raw SDK errors
    }
  }
}

/** Factory: dev stub everywhere except production (same posture as makeOtpSender). */
export function makePhotoStorage(): PhotoStorage {
  return config.NODE_ENV === 'production' ? new R2PhotoStorage() : new DevPhotoStorage();
}

/** Module singleton — services import this; tests reach the Dev impl through it. */
export const photoStorage: PhotoStorage = makePhotoStorage();
