/*
  Warnings:

  - Added the required column `requiredSkill` to the `Service` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "technicianId" TEXT;

-- requiredSkill: add nullable, backfill existing rows by category name, then enforce NOT NULL
ALTER TABLE "Service" ADD COLUMN "requiredSkill" "ServiceSkill";
UPDATE "Service" s SET "requiredSkill" =
  CASE
    WHEN c."name" ILIKE '%AC%'        THEN 'AC'::"ServiceSkill"
    WHEN c."name" ILIKE '%fan%'       THEN 'FAN'::"ServiceSkill"
    WHEN c."name" ILIKE '%electric%'  THEN 'ELECTRICAL'::"ServiceSkill"
    WHEN c."name" ILIKE '%wir%'       THEN 'WIRING'::"ServiceSkill"
    ELSE 'APPLIANCE'::"ServiceSkill"
  END
  FROM "ServiceCategory" c WHERE s."categoryId" = c."id";
ALTER TABLE "Service" ALTER COLUMN "requiredSkill" SET NOT NULL;

-- CreateTable
CREATE TABLE "JobSkip" (
    "id" TEXT NOT NULL,
    "technicianId" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "JobSkip_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "JobSkip_technicianId_idx" ON "JobSkip"("technicianId");

-- CreateIndex
CREATE UNIQUE INDEX "JobSkip_technicianId_bookingId_key" ON "JobSkip"("technicianId", "bookingId");

-- AddForeignKey
ALTER TABLE "Booking" ADD CONSTRAINT "Booking_technicianId_fkey" FOREIGN KEY ("technicianId") REFERENCES "Technician"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "JobSkip" ADD CONSTRAINT "JobSkip_technicianId_fkey" FOREIGN KEY ("technicianId") REFERENCES "Technician"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "JobSkip" ADD CONSTRAINT "JobSkip_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
