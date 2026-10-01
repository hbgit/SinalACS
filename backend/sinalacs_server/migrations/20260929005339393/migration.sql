BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "data_subject_requests" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "requestType" text NOT NULL,
    "detailsEncrypted" text NOT NULL,
    "detailsKeyVersion" bigint NOT NULL,
    "status" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "dueAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE INDEX "data_subject_requests_user_id_type_idx" ON "data_subject_requests" USING btree ("userId", "requestType");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "data_subject_requests"
    ADD CONSTRAINT "data_subject_requests_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260929005339393', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260929005339393', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
