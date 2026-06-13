-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "arrivalLat" DOUBLE PRECISION,
ADD COLUMN     "arrivalLng" DOUBLE PRECISION,
ADD COLUMN     "arrivedAt" TIMESTAMP(3),
ADD COLUMN     "visitFeeLockedAt" TIMESTAMP(3);
