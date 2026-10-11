BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "acs_upload_tokens" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "tokenHash" text NOT NULL,
    "deviceId" text NOT NULL,
    "issuedAt" timestamp without time zone NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    "revokedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "acs_upload_tokens_hash_key" ON "acs_upload_tokens" USING btree ("tokenHash");
CREATE INDEX "acs_upload_tokens_user_device_idx" ON "acs_upload_tokens" USING btree ("userId", "deviceId");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "acs_upload_tokens"
    ADD CONSTRAINT "acs_upload_tokens_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261004014924364', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261004014924364', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
