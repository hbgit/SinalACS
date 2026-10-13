BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "alerts" ADD COLUMN "escalatedAt" timestamp without time zone;
ALTER TABLE "alerts" ADD COLUMN "escalatedBy" uuid;
ALTER TABLE "alerts" ADD COLUMN "escalationReason" text;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261012004814823', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261012004814823', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
