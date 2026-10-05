BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "user_credentials" ADD COLUMN "lockStreak" bigint NOT NULL DEFAULT 0;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261005204222939', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261005204222939', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
