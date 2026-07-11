-- CreateEnum
CREATE TYPE "PhotoKind" AS ENUM ('DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP');

-- AlterEnum
ALTER TYPE "AuditAction" ADD VALUE 'PHOTO_UPLOADED';

-- CreateTable
CREATE TABLE "PhotoEvidence" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "kind" "PhotoKind" NOT NULL,
    "r2Key" TEXT NOT NULL,
    "geotagLat" DOUBLE PRECISION,
    "geotagLng" DOUBLE PRECISION,
    "capturedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PhotoEvidence_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PhotoEvidence_bookingId_kind_idx" ON "PhotoEvidence"("bookingId", "kind");

-- AddForeignKey
ALTER TABLE "PhotoEvidence" ADD CONSTRAINT "PhotoEvidence_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
