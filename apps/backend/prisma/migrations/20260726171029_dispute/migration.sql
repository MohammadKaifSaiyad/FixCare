/*
  Warnings:

  - A unique constraint covering the columns `[razorpayRefundId]` on the table `Payment` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateEnum
CREATE TYPE "DisputeStatus" AS ENUM ('OPEN', 'RESOLVED');

-- CreateEnum
CREATE TYPE "DisputeOutcome" AS ENUM ('FAVOR_CUSTOMER', 'FAVOR_TECHNICIAN', 'PARTIAL');

-- AlterEnum
ALTER TYPE "AuditAction" ADD VALUE 'DISPUTE_EVENT';

-- AlterEnum
ALTER TYPE "LedgerEntryType" ADD VALUE 'DISPUTE_REVERSAL';

-- AlterTable
ALTER TABLE "Payment" ADD COLUMN     "razorpayRefundId" TEXT;

-- CreateTable
CREATE TABLE "Dispute" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "raisedByUserId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "status" "DisputeStatus" NOT NULL DEFAULT 'OPEN',
    "outcome" "DisputeOutcome",
    "refundPaise" INTEGER,
    "resolvedByUserId" TEXT,
    "resolvedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Dispute_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Dispute_bookingId_idx" ON "Dispute"("bookingId");

-- CreateIndex
CREATE INDEX "Dispute_status_idx" ON "Dispute"("status");

-- CreateIndex
CREATE UNIQUE INDEX "Payment_razorpayRefundId_key" ON "Payment"("razorpayRefundId");

-- AddForeignKey
ALTER TABLE "Dispute" ADD CONSTRAINT "Dispute_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- One OPEN dispute per booking — the DB backstops a double-raise race (partial unique index).
CREATE UNIQUE INDEX "Dispute_one_open_per_booking" ON "Dispute"("bookingId") WHERE status = 'OPEN';
