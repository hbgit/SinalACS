BEGIN;

--
-- ACTION ALTER TABLE
--
CREATE UNIQUE INDEX "acs_enrollment_id_key" ON "acs" USING btree ("enrollmentId");
--
-- ACTION CREATE TABLE
--
CREATE TABLE "user_credentials" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "passwordHash" text NOT NULL,
    "passwordSalt" text NOT NULL,
    "memoryKb" bigint NOT NULL,
    "iterations" bigint NOT NULL,
    "parallelism" bigint NOT NULL,
    "failedAttempts" bigint NOT NULL,
    "lockedUntil" timestamp without time zone,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "user_credentials_user_id_key" ON "user_credentials" USING btree ("userId");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "user_credentials"
    ADD CONSTRAINT "user_credentials_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260919001437559', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260919001437559', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
