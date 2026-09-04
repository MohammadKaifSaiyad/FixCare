import type { Booking, BookingPart, PhotoEvidence, Payment, Dispute } from '@prisma/client';
import { maskPhone } from '../../shared/utils/mask.js';
import { computeEstimate, type Estimate } from './estimate.js';
import { photoStorage } from '../../shared/third-party/r2-storage.js';

export interface PhotoSummary { kind: PhotoEvidence['kind']; capturedAt: string; url: string }

/** Map ACTIVE photo rows to summaries with signed read URLs. Async because presignRead signs. */
export async function toPhotoSummaries(photos: PhotoEvidence[]): Promise<PhotoSummary[]> {
  return Promise.all(photos.map(async (p) => ({ kind: p.kind, capturedAt: p.capturedAt.toISOString(), url: await photoStorage.presignRead(p.r2Key) })));
}

export interface BookingDto {
  id: string;
  bookingNumber: string;
  state: Booking['state'];
  scheduledSlot: string; // ISO string
  visitFeePaise: number;
  laborPaise: number;
  laborTier: Booking['laborTier'];
  service: { id: string; name: string };
  zone: { id: string; name: string };
  address: { id: string };
  // Present once a technician has accepted. Customer sees the technician's real name (per core-flow
  // "what customer sees") but the technician's phone is masked (directional masking, Golden Rule 7).
  technician?: { name: string; maskedPhone: string };
  // Set once a technician has recorded a diagnosis (snapshot name, not a live FK lookup).
  diagnosis: { issueName: string } | null;
  // The price-snapshotted parts cart. Empty until the technician adds parts post-diagnosis.
  parts: { id: string; sku: string; name: string; ceilingPricePaise: number; qty: number }[];
  // Computed from the labor/visit-fee snapshots + the cart. Labor-only (parts []) until diagnosis.
  estimate: Estimate;
  // Active photo evidence with SHORT-LIVED signed read URLs (15 min) — raw r2Key never leaves the API.
  photos: PhotoSummary[];
  // Latest payment attempt (null before any). Gateway ids never leak here — the app gets what
  // checkout needs from POST /pay, and everything else is internal evidence.
  payment: PaymentSummary | null;
  // Latest dispute on this booking (null if none raised). The customer's own free-text reason is
  // NEVER surfaced here — it stays internal/admin-only (B7 dispute detail is admin-side only).
  dispute: DisputeSummary | null;
}

export interface PaymentSummary { status: Payment['status']; method: Payment['method']; amountPaise: number }

export interface DisputeSummary { status: Dispute['status']; outcome: Dispute['outcome']; refundPaise: number | null }

export function toBookingDto(
  b: Booking,
  tech?: { name: string; phone: string },
  parts: BookingPart[] = [],
  photos: PhotoSummary[] = [],
  payment: PaymentSummary | null = null,
  dispute: DisputeSummary | null = null,
): BookingDto {
  return {
    id: b.id,
    bookingNumber: b.bookingNumber,
    state: b.state,
    scheduledSlot: b.scheduledSlot.toISOString(),
    visitFeePaise: b.visitFeePaise,
    laborPaise: b.laborPaise,
    laborTier: b.laborTier,
    service: { id: b.serviceId, name: b.serviceName },
    zone: { id: b.zoneId, name: b.zoneName },
    address: { id: b.addressId },
    ...(tech ? { technician: { name: tech.name, maskedPhone: maskPhone(tech.phone) } } : {}),
    diagnosis: b.diagnosedIssueName ? { issueName: b.diagnosedIssueName } : null,
    parts: parts.map((p) => ({ id: p.id, sku: p.sku, name: p.name, ceilingPricePaise: p.ceilingPricePaise, qty: p.qty })),
    estimate: computeEstimate(b, parts),
    photos,
    payment,
    dispute,
  };
}
