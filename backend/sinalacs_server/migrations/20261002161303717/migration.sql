BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "user_credentials" ADD COLUMN "totpSecretEncrypted" text;
ALTER TABLE "user_credentials" ADD COLUMN "totpKeyVersion" bigint;
ALTER TABLE "user_credentials" ADD COLUMN "totpEnabledAt" timestamp without time zone;
ALTER TABLE "user_credentials" ADD COLUMN "totpLastStep" bigint;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261002161303717', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261002161303717', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
