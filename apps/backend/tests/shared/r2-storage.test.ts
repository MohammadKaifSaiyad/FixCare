import { describe, expect, it } from 'vitest';
import { DevPhotoStorage, photoStorage } from '../../src/shared/third-party/r2-storage.js';

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
