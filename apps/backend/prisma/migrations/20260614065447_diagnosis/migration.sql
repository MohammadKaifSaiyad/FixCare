-- AlterEnum
ALTER TYPE "AuditAction" ADD VALUE 'DIAGNOSIS_UPDATED';

-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "declinedAt" TIMESTAMP(3),
ADD COLUMN     "diagnosedAt" TIMESTAMP(3),
ADD COLUMN     "diagnosedIssueId" TEXT,
ADD COLUMN     "diagnosedIssueName" TEXT;

-- CreateTable
CREATE TABLE "DiagnosedIssue" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "status" "CatalogStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "DiagnosedIssue_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BookingPart" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "partsCatalogId" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "ceilingPricePaise" INTEGER NOT NULL,
    "qty" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "BookingPart_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DiagnosedIssue_categoryId_idx" ON "DiagnosedIssue"("categoryId");

-- CreateIndex
CREATE UNIQUE INDEX "DiagnosedIssue_categoryId_name_key" ON "DiagnosedIssue"("categoryId", "name");

-- CreateIndex
CREATE INDEX "BookingPart_bookingId_idx" ON "BookingPart"("bookingId");

-- AddForeignKey
ALTER TABLE "Booking" ADD CONSTRAINT "Booking_diagnosedIssueId_fkey" FOREIGN KEY ("diagnosedIssueId") REFERENCES "DiagnosedIssue"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DiagnosedIssue" ADD CONSTRAINT "DiagnosedIssue_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "ServiceCategory"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "BookingPart" ADD CONSTRAINT "BookingPart_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
