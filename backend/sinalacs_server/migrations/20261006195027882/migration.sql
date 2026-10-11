BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "staff_accounts" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "enrollmentId" text NOT NULL,
    "active" boolean NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "staff_accounts_enrollment_id_key" ON "staff_accounts" USING btree ("enrollmentId");


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261006195027882', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261006195027882', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
