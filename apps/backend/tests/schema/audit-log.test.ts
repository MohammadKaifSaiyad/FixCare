import { beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

describe('AuditLog model', () => {
  beforeEach(resetDb);

  it('records an enumerated action with PII-free metadata', async () => {
    const row = await prisma.auditLog.create({
      data: {
        action: 'ADMIN_LEVEL_CHANGED',
        actorType: 'ADMIN',
        actorId: 'admin-1',
        subjectId: 'admin-2',
        metadata: { fromLevel: 'SUPPORT', toLevel: 'MANAGER' },
      },
    });
    expect(row.action).toBe('ADMIN_LEVEL_CHANGED');
    expect(row.createdAt).toBeInstanceOf(Date);
  });

  it('allows a SYSTEM actor with null actorId', async () => {
    const row = await prisma.auditLog.create({
      data: { action: 'REFRESH_TOKEN_REUSE_DETECTED', actorType: 'SYSTEM' },
    });
    expect(row.actorId).toBeNull();
  });
});
