BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "ubs" ADD COLUMN "contactPhone" text;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261002153125316', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261002153125316', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
