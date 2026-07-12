import { describe, expect, it } from 'vitest';
import { DevPhotoStorage, R2PhotoStorage, photoStorage } from '../../src/shared/third-party/r2-storage.js';

describe('DevPhotoStorage', () => {
  it('presigns an upload with a 24h expiry and a deterministic dev URL', async () => {
    const s = new DevPhotoStorage();
    const { url, expiresAt } = await s.presignUpload('jobs/b1/DIAGNOSIS_OVERVIEW-x.jpg', 100_000);
    expect(url).toContain('jobs%2Fb1%2FDIAGNOSIS_OVERVIEW-x.jpg');
    expect(expiresAt.getTime()).toBeGreaterThan(Date.now() + 23 * 3600 * 1000);
  });

  it('objectExists is false until markUploaded', async () => {
    const s = new DevPhotoStorage();
    expect(await s.objectExists('jobs/b1/k.jpg')).toBe(false);
    s.markUploaded('jobs/b1/k.jpg');
    expect(await s.objectExists('jobs/b1/k.jpg')).toBe(true);
  });

  it('presignRead returns a dev read URL', async () => {
    const s = new DevPhotoStorage();
    expect(await s.presignRead('jobs/b1/k.jpg')).toContain('read');
  });

  it('the module singleton is the Dev impl outside production', () => {
    expect(photoStorage).toBeInstanceOf(DevPhotoStorage);
  });
});

describe('R2PhotoStorage boot safety', () => {
  it('constructs WITHOUT R2 creds (production must boot before R2 is provisioned); first USE fails with a clear config error', async () => {
    // Creds are checked lazily on first use, never in the constructor — a production deploy
    // before the R2 account exists must not crash the whole API at import time.
    const s = new R2PhotoStorage();
    await expect(s.objectExists('jobs/x/k.jpg')).rejects.toThrow(/R2 storage is not configured/);
    await expect(s.presignRead('jobs/x/k.jpg')).rejects.toThrow(/R2 storage is not configured/);
  });
});
