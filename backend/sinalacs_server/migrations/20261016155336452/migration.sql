BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "alerts" ADD COLUMN "resolvedAt" timestamp without time zone;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261016155336452', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261016155336452', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
