import type { Booking, BookingPart } from '@prisma/client';
import { maskPhone } from '../../shared/utils/mask.js';
import { computeEstimate, type Estimate } from './estimate.js';

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
}

export function toBookingDto(
  b: Booking,
  tech?: { name: string; phone: string },
  parts: BookingPart[] = [],
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
  };
}
