-- AlterEnum
ALTER TYPE "AuditAction" ADD VALUE 'TECHNICIAN_STATUS_CHANGED';

-- AlterTable
ALTER TABLE "Technician" ADD COLUMN     "reviewNote" TEXT,
ADD COLUMN     "reviewedAt" TIMESTAMP(3),
ADD COLUMN     "submittedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "TechnicianZone" (
    "technicianId" TEXT NOT NULL,
    "zoneId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TechnicianZone_pkey" PRIMARY KEY ("technicianId","zoneId")
);

-- CreateIndex
CREATE INDEX "TechnicianZone_zoneId_idx" ON "TechnicianZone"("zoneId");

-- AddForeignKey
ALTER TABLE "TechnicianZone" ADD CONSTRAINT "TechnicianZone_technicianId_fkey" FOREIGN KEY ("technicianId") REFERENCES "Technician"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TechnicianZone" ADD CONSTRAINT "TechnicianZone_zoneId_fkey" FOREIGN KEY ("zoneId") REFERENCES "Zone"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
