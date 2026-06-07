import type { Address } from '@prisma/client';
import type { Serviceability } from './serviceability.service.js';

export interface AddressDto {
  id: string;
  label: string;
  line1: string;
  line2: string | null;
  landmark: string | null;
  pincode: string;
  lat: number | null;
  lng: number | null;
  isDefault: boolean;
  status: Address['status'];
  serviceable: boolean;
  zone: Serviceability['zone']; // { id, name, visitFeePaise } | null
  message?: string; // present only when unserviceable
}

export function toAddressDto(a: Address, s: Serviceability): AddressDto {
  return {
    id: a.id,
    label: a.label,
    line1: a.line1,
    line2: a.line2,
    landmark: a.landmark,
    pincode: a.pincode,
    lat: a.lat,
    lng: a.lng,
    isDefault: a.isDefault,
    status: a.status,
    serviceable: s.serviceable,
    zone: s.zone,
    ...(s.message !== undefined ? { message: s.message } : {}),
  };
}
