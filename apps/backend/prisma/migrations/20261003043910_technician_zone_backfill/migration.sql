-- Behavior-preserving backfill: before technician zones existed a VERIFIED technician was offered every zone's jobs.
-- Give every existing VERIFIED/SUSPENDED technician every ACTIVE zone; ops narrows them with the admin PATCH.
INSERT INTO "TechnicianZone" ("technicianId","zoneId") SELECT t."id", z."id" FROM "Technician" t CROSS JOIN "Zone" z WHERE t."status" IN ('VERIFIED','SUSPENDED') AND t."deletedAt" IS NULL AND z."status" = 'ACTIVE' AND z."deletedAt" IS NULL ON CONFLICT DO NOTHING;
