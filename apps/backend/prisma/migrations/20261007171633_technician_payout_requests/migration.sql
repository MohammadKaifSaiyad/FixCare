-- CreateEnum
CREATE TYPE "PayoutRequestStatus" AS ENUM ('REQUESTED', 'PAID', 'REJECTED');

-- CreateTable
CREATE TABLE "PayoutRequest" (
    "id" TEXT NOT NULL,
    "technicianId" TEXT NOT NULL,
    "amountPaise" INTEGER NOT NULL,
    "status" "PayoutRequestStatus" NOT NULL DEFAULT 'REQUESTED',
    "reviewNote" TEXT,
    "reviewedBy" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "payoutEntryId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PayoutRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PayoutRequest_payoutEntryId_key" ON "PayoutRequest"("payoutEntryId");

-- CreateIndex
CREATE INDEX "PayoutRequest_technicianId_createdAt_idx" ON "PayoutRequest"("technicianId", "createdAt");

-- CreateIndex
CREATE INDEX "PayoutRequest_status_createdAt_idx" ON "PayoutRequest"("status", "createdAt");

-- AddForeignKey
ALTER TABLE "PayoutRequest" ADD CONSTRAINT "PayoutRequest_technicianId_fkey" FOREIGN KEY ("technicianId") REFERENCES "Technician"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
