-- AlterEnum
ALTER TYPE "PaymentMethod" ADD VALUE 'CASH';

-- AlterTable
ALTER TABLE "Payment" ALTER COLUMN "razorpayOrderId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "Technician" ADD COLUMN     "cashDebtPaise" INTEGER NOT NULL DEFAULT 0;
