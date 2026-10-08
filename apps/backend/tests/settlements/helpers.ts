import type { buildApp } from '../../src/app.js';
import type { BookingState, LedgerEntryType } from '@prisma/client';
import { prisma } from '../schema/helpers.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

type App = Awaited<ReturnType<typeof buildApp>>;
export function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** A booking assigned to `technicianId`, forced into `state` (fixture shortcut — the state machine has its own tests).
 *  labor 60000 / visit fee 14900 from seedBookable. */
export async function assignedBooking(app: App, technicianId: string, state: BookingState, extra: { paidAt?: Date | null; declinedAt?: Date } = {}) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const b = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json() as { id: string; bookingNumber: string };
  await prisma.booking.update({ where: { id: b.id }, data: { state, technicianId, ...extra } });
  return { bookingId: b.id, bookingNumber: b.bookingNumber, serviceName: f.service.name };
}

/** Seed ledger rows directly (amounts positive, as the ledger stores them). */
export async function ledger(technicianId: string, rows: { type: LedgerEntryType; amountPaise: number; bookingId?: string; createdAt?: Date; metadata?: object }[]) {
  for (const r of rows) await prisma.ledgerEntry.create({ data: { technicianId, type: r.type, amountPaise: r.amountPaise, bookingId: r.bookingId ?? null, ...(r.metadata ? { metadata: r.metadata } : {}), ...(r.createdAt ? { createdAt: r.createdAt } : {}) } });
}

export { makeTechnician };
