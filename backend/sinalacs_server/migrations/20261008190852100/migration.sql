BEGIN;

--
-- ACTION ALTER TABLE
--
ALTER TABLE "data_subject_requests" ADD COLUMN "decidedAt" timestamp without time zone;
ALTER TABLE "data_subject_requests" ADD COLUMN "decidedBy" uuid;
ALTER TABLE "data_subject_requests" ADD COLUMN "resolutionEncrypted" text;
ALTER TABLE "data_subject_requests" ADD COLUMN "resolutionKeyVersion" bigint;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "data_subject_requests"
    ADD CONSTRAINT "data_subject_requests_fk_1"
    FOREIGN KEY("decidedBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261008190852100', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261008190852100', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
