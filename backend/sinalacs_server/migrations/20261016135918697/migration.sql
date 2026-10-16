BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "triage_sessions" DROP COLUMN "resultRisk";
ALTER TABLE "triage_sessions" DROP COLUMN "resultDisplay";
ALTER TABLE "triage_sessions" ADD COLUMN "resultRiskEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "triage_sessions" ADD COLUMN "resultRiskKeyVersion" bigint NOT NULL DEFAULT 1;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261016135918697', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261016135918697', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
