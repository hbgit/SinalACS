BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "patients" DROP COLUMN "emergencyContact";
ALTER TABLE "patients" ADD COLUMN "emergencyContactEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "patients" ADD COLUMN "emergencyContactKeyVersion" bigint NOT NULL DEFAULT 1;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261007153048060', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261007153048060', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
