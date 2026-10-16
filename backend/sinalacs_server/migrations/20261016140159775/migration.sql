BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "visits" DROP COLUMN "riskLevelBefore";
ALTER TABLE "visits" DROP COLUMN "riskLevelAfter";
ALTER TABLE "visits" ADD COLUMN "riskLevelBeforeEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "visits" ADD COLUMN "riskLevelBeforeKeyVersion" bigint NOT NULL DEFAULT 1;
ALTER TABLE "visits" ADD COLUMN "riskLevelAfterEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "visits" ADD COLUMN "riskLevelAfterKeyVersion" bigint NOT NULL DEFAULT 1;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261016140159775', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261016140159775', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
