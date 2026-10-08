BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "staff_accounts" ADD COLUMN "activationCodeHash" text;
ALTER TABLE "staff_accounts" ADD COLUMN "activationCodeExpiresAt" timestamp without time zone;
ALTER TABLE "staff_accounts" ADD COLUMN "activationCodeIssuedBy" text;
ALTER TABLE "staff_accounts" ADD COLUMN "activationCodeIssuedAt" timestamp without time zone;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261007153247428', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261007153247428', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
