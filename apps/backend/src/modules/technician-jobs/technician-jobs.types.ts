import type { Booking, Address, ServiceSkill, BookingPart } from '@prisma/client';
import { maskPhone } from '../../shared/utils/mask.js';
import type { PhotoSummary } from '../bookings/bookings.types.js';

export interface TechnicianJobDto {
  id: string;
  bookingNumber: string;
  state: Booking['state'];
  scheduledSlot: string;
  service: { name: string; requiredSkill: ServiceSkill; categoryId: string };
  zone: { name: string };
  visitFeePaise: number;
  laborPaise: number;
  address: { line1: string; line2: string | null; landmark: string | null; pincode: string };
  customer: { maskedPhone: string };
  photos: PhotoSummary[];
}

/** Masked technician-facing view of a booking. `booking` carries the snapshot fields; `address` is
 *  the booking's address row; `service` is the joined Service row (requiredSkill + categoryId); `customerPhone` is the
 *  customer User.phone — masked here, NEVER returned raw (Golden Rule 7). No customer name. */
export function toTechnicianJobDto(
  booking: Booking,
  address: Address,
  service: { requiredSkill: ServiceSkill; categoryId: string },
  customerPhone: string,
  photos: PhotoSummary[] = [],
): TechnicianJobDto {
  return {
    id: booking.id,
    bookingNumber: booking.bookingNumber,
    state: booking.state,
    scheduledSlot: booking.scheduledSlot.toISOString(),
    service: { name: booking.serviceName, requiredSkill: service.requiredSkill, categoryId: service.categoryId },
    zone: { name: booking.zoneName },
    visitFeePaise: booking.visitFeePaise,
    laborPaise: booking.laborPaise,
    address: { line1: address.line1, line2: address.line2, landmark: address.landmark, pincode: address.pincode },
    customer: { maskedPhone: maskPhone(customerPhone) },
    photos,
  };
}

/** One cart line as the technician sees it — the snapshot price, never a live catalog read. */
export interface TechnicianJobPartLine {
  id: string;
  partsCatalogId: string;
  sku: string;
  name: string;
  qty: number;
  ceilingPricePaise: number;
}

/** GET /technician/jobs/:id — the list DTO plus the job's parts cart (open while ARRIVED, frozen after). */
export interface TechnicianJobDetailDto extends TechnicianJobDto {
  parts: TechnicianJobPartLine[];
}

export function toTechnicianJobDetailDto(
  booking: Booking,
  address: Address,
  service: { requiredSkill: ServiceSkill; categoryId: string },
  customerPhone: string,
  photos: PhotoSummary[],
  parts: BookingPart[],
): TechnicianJobDetailDto {
  return {
    ...toTechnicianJobDto(booking, address, service, customerPhone, photos),
    parts: parts.map((p) => ({ id: p.id, partsCatalogId: p.partsCatalogId, sku: p.sku, name: p.name, qty: p.qty, ceilingPricePaise: p.ceilingPricePaise })),
  };
}
