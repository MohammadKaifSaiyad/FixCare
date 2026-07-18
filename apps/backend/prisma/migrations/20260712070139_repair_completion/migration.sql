-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "PhotoKind" ADD VALUE 'REPAIR_OLD_PART';
ALTER TYPE "PhotoKind" ADD VALUE 'REPAIR_NEW_PACKAGING';
ALTER TYPE "PhotoKind" ADD VALUE 'REPAIR_INSTALLED';

-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "confirmedAt" TIMESTAMP(3),
ADD COLUMN     "repairCompletedAt" TIMESTAMP(3),
ADD COLUMN     "repairStartedAt" TIMESTAMP(3);
