-- CreateTable
CREATE TABLE "PincodeZone" (
    "id" TEXT NOT NULL,
    "pincode" TEXT NOT NULL,
    "zoneId" TEXT NOT NULL,
    "status" "CatalogStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "PincodeZone_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PincodeZone_pincode_key" ON "PincodeZone"("pincode");

-- CreateIndex
CREATE INDEX "PincodeZone_zoneId_idx" ON "PincodeZone"("zoneId");

-- AddForeignKey
ALTER TABLE "PincodeZone" ADD CONSTRAINT "PincodeZone_zoneId_fkey" FOREIGN KEY ("zoneId") REFERENCES "Zone"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
