import type { Booking } from '@prisma/client';

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
}

export function toBookingDto(b: Booking): BookingDto {
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
  };
}
