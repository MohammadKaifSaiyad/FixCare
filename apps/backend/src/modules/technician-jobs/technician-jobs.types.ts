import type { Booking, Address, ServiceSkill } from '@prisma/client';
import { maskPhone } from '../../shared/utils/mask.js';
import type { PhotoSummary } from '../bookings/bookings.types.js';

export interface TechnicianJobDto {
  id: string;
  bookingNumber: string;
  state: Booking['state'];
  scheduledSlot: string;
  service: { name: string; requiredSkill: ServiceSkill };
  zone: { name: string };
  visitFeePaise: number;
  laborPaise: number;
  address: { line1: string; line2: string | null; landmark: string | null; pincode: string };
  customer: { maskedPhone: string };
  photos: PhotoSummary[];
}

/** Masked technician-facing view of a booking. `booking` carries the snapshot fields; `address` is
 *  the booking's address row; `requiredSkill` comes from the joined Service; `customerPhone` is the
 *  customer User.phone — masked here, NEVER returned raw (Golden Rule 7). No customer name. */
export function toTechnicianJobDto(
  booking: Booking,
  address: Address,
  requiredSkill: ServiceSkill,
  customerPhone: string,
  photos: PhotoSummary[] = [],
): TechnicianJobDto {
  return {
    id: booking.id,
    bookingNumber: booking.bookingNumber,
    state: booking.state,
    scheduledSlot: booking.scheduledSlot.toISOString(),
    service: { name: booking.serviceName, requiredSkill },
    zone: { name: booking.zoneName },
    visitFeePaise: booking.visitFeePaise,
    laborPaise: booking.laborPaise,
    address: { line1: address.line1, line2: address.line2, landmark: address.landmark, pincode: address.pincode },
    customer: { maskedPhone: maskPhone(customerPhone) },
    photos,
  };
}
