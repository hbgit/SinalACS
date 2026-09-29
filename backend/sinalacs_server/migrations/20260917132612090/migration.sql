BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "enrollment_tokens" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "tokenHash" text NOT NULL,
    "patientId" uuid NOT NULL,
    "microAreaId" uuid NOT NULL,
    "createdByAcsId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    "consumedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "enrollment_tokens_token_hash_key" ON "enrollment_tokens" USING btree ("tokenHash");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "enrollment_tokens"
    ADD CONSTRAINT "enrollment_tokens_fk_0"
    FOREIGN KEY("patientId")
    REFERENCES "patients"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "enrollment_tokens"
    ADD CONSTRAINT "enrollment_tokens_fk_1"
    FOREIGN KEY("createdByAcsId")
    REFERENCES "acs"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260917132612090', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260917132612090', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
