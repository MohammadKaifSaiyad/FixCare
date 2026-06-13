/** Max distance (metres) between the technician's arrive-tap GPS and the customer address for the
 *  arrival to count as on-site. Shared by the technician arrive-tap gate and the customer
 *  confirm-arrival evidence re-derivation so the two never drift. */
export const ARRIVAL_GEOFENCE_METERS = 200;
