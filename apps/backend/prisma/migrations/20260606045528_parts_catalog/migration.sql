-- CreateTable
CREATE TABLE "PartsCatalog" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "categoryId" TEXT,
    "ceilingPricePaise" INTEGER NOT NULL,
    "status" "CatalogStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),

    CONSTRAINT "PartsCatalog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PartsCatalog_sku_key" ON "PartsCatalog"("sku");

-- CreateIndex
CREATE INDEX "PartsCatalog_categoryId_idx" ON "PartsCatalog"("categoryId");

-- AddForeignKey
ALTER TABLE "PartsCatalog" ADD CONSTRAINT "PartsCatalog_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "ServiceCategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;
