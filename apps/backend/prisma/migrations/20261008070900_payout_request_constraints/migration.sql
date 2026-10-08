-- CreateIndex
CREATE UNIQUE INDEX "PayoutRequest_transferReference_key" ON "PayoutRequest"("transferReference");

-- One OPEN payout request per technician — the DB backstops the app-level check under the technician row lock
-- (partial unique index, same pattern as Dispute_one_open_per_booking).
CREATE UNIQUE INDEX "PayoutRequest_one_open_per_technician" ON "PayoutRequest"("technicianId") WHERE status = 'REQUESTED';

-- A payout request is always for a positive amount.
ALTER TABLE "PayoutRequest" ADD CONSTRAINT "PayoutRequest_amountPaise_positive" CHECK ("amountPaise" > 0);
