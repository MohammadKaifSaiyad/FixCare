-- DropForeignKey
ALTER TABLE "LedgerEntry" DROP CONSTRAINT "LedgerEntry_bookingId_fkey";

-- CreateIndex
CREATE INDEX "LedgerEntry_technicianId_type_idx" ON "LedgerEntry"("technicianId", "type");

-- AddForeignKey
ALTER TABLE "LedgerEntry" ADD CONSTRAINT "LedgerEntry_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
