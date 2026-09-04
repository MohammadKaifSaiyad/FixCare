-- DropIndex
DROP INDEX "Dispute_status_idx";

-- CreateIndex
CREATE INDEX "Dispute_status_createdAt_idx" ON "Dispute"("status", "createdAt");
