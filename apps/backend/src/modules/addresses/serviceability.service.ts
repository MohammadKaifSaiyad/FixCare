import { prisma } from '../../shared/database/prisma.js';

export const OUT_OF_AREA_MESSAGE = "We don't serve this area yet";

export interface ServiceabilityZone { id: string; name: string; visitFeePaise: number; }
export interface Serviceability {
  serviceable: boolean;
  zone: ServiceabilityZone | null;
  message?: string;
}

/** Resolve a pincode to its serviceable zone using the LIVE PincodeZone map.
 *  Unserviceable if no active mapping, or the mapping/zone is soft-deleted/INACTIVE. */
export async function resolvePincode(pincode: string): Promise<Serviceability> {
  const mapping = await prisma.pincodeZone.findFirst({
    where: {
      pincode,
      deletedAt: null,
      status: 'ACTIVE',
      zone: { deletedAt: null, status: 'ACTIVE' },
    },
    include: { zone: true },
  });
  if (!mapping) return { serviceable: false, zone: null, message: OUT_OF_AREA_MESSAGE };
  return {
    serviceable: true,
    zone: { id: mapping.zone.id, name: mapping.zone.name, visitFeePaise: mapping.zone.visitFeePaise },
  };
}
