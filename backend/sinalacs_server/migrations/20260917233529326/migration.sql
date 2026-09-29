BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "visits" ADD COLUMN "arrivalMethod" text NOT NULL DEFAULT 'manual'::text;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260917233529326', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260917233529326', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
