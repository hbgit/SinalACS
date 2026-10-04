BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "visits" ADD COLUMN "authorship" text NOT NULL DEFAULT 'acs'::text;
ALTER TABLE "visits" ADD COLUMN "originDeviceId" text;
ALTER TABLE "visits" ALTER COLUMN "acsId" DROP NOT NULL;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261004013108186', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261004013108186', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
