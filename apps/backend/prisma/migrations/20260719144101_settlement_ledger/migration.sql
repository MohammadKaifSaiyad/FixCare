-- CreateEnum
CREATE TYPE "LedgerEntryType" AS ENUM ('EARNING_CREDIT', 'COMMISSION', 'CASH_COLLECTED', 'CASH_DEBT_OFFSET', 'PAYOUT', 'DEBT_REPAYMENT');

-- AlterEnum
ALTER TYPE "AuditAction" ADD VALUE 'SETTLEMENT_EVENT';

-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "closedAt" TIMESTAMP(3),
ADD COLUMN     "paidAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "LedgerEntry" (
    "id" TEXT NOT NULL,
    "technicianId" TEXT NOT NULL,
    "bookingId" TEXT,
    "type" "LedgerEntryType" NOT NULL,
    "amountPaise" INTEGER NOT NULL,
    "metadata" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "LedgerEntry_technicianId_createdAt_idx" ON "LedgerEntry"("technicianId", "createdAt");

-- CreateIndex
CREATE INDEX "Payment_method_status_capturedAt_idx" ON "Payment"("method", "status", "capturedAt");

-- AddForeignKey
ALTER TABLE "LedgerEntry" ADD CONSTRAINT "LedgerEntry_technicianId_fkey" FOREIGN KEY ("technicianId") REFERENCES "Technician"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LedgerEntry" ADD CONSTRAINT "LedgerEntry_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- B6b carry-forward: a settlement bug must never produce a negative cached balance — a negative
-- value would silently disable BOTH cash gates (debt limit + velocity) in B6b's checks.
ALTER TABLE "Technician" ADD CONSTRAINT "Technician_cashDebtPaise_nonnegative" CHECK ("cashDebtPaise" >= 0);
