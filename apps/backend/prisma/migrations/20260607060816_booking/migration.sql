-- CreateEnum
CREATE TYPE "BookingState" AS ENUM ('CREATED', 'DISPATCHED', 'ACCEPTED', 'EN_ROUTE', 'ARRIVED', 'DIAGNOSED', 'CUSTOMER_APPROVED', 'PARTS_REQUESTED', 'PARTS_ACQUIRED', 'REPAIR_IN_PROGRESS', 'REPAIR_COMPLETE', 'CUSTOMER_CONFIRMED', 'PAYMENT_RECEIVED', 'CLOSED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN', 'DECLINED_BY_CUSTOMER', 'DISPUTED');

-- AlterEnum
ALTER TYPE "AuditAction" ADD VALUE 'BOOKING_STATE_CHANGED';

-- CreateTable
CREATE TABLE "Booking" (
    "id" TEXT NOT NULL,
    "bookingNumber" TEXT NOT NULL,
    "customerId" TEXT NOT NULL,
    "addressId" TEXT NOT NULL,
    "serviceId" TEXT NOT NULL,
    "zoneId" TEXT NOT NULL,
    "zoneName" TEXT NOT NULL,
    "serviceName" TEXT NOT NULL,
    "visitFeePaise" INTEGER NOT NULL,
    "laborPaise" INTEGER NOT NULL,
    "laborTier" "LaborTier" NOT NULL,
    "scheduledSlot" TIMESTAMP(3) NOT NULL,
    "state" "BookingState" NOT NULL DEFAULT 'CREATED',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "Booking_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Booking_bookingNumber_key" ON "Booking"("bookingNumber");

-- CreateIndex
CREATE INDEX "Booking_customerId_idx" ON "Booking"("customerId");

-- CreateIndex
CREATE INDEX "Booking_state_idx" ON "Booking"("state");

-- AddForeignKey
ALTER TABLE "Booking" ADD CONSTRAINT "Booking_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "Customer"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Booking" ADD CONSTRAINT "Booking_addressId_fkey" FOREIGN KEY ("addressId") REFERENCES "Address"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Booking" ADD CONSTRAINT "Booking_serviceId_fkey" FOREIGN KEY ("serviceId") REFERENCES "Service"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
