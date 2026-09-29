BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "patients" DROP COLUMN "chronicConditions";
ALTER TABLE "patients" ADD COLUMN "chronicConditionsEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "patients" ADD COLUMN "chronicConditionsKeyVersion" bigint NOT NULL DEFAULT 1;
--
-- ACTION ALTER TABLE
--
ALTER TABLE "triage_sessions" DROP COLUMN "answers";
ALTER TABLE "triage_sessions" ADD COLUMN "answersEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "triage_sessions" ADD COLUMN "answersKeyVersion" bigint NOT NULL DEFAULT 1;
--
-- ACTION ALTER TABLE
--
ALTER TABLE "visits" DROP COLUMN "notes";
ALTER TABLE "visits" ADD COLUMN "notesEncrypted" text NOT NULL DEFAULT ''::text;
ALTER TABLE "visits" ADD COLUMN "notesKeyVersion" bigint NOT NULL DEFAULT 1;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260917191250458', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260917191250458', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
