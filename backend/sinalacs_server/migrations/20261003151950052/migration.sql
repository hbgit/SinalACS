BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "acs_refresh_tokens" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "familyId" uuid NOT NULL,
    "tokenHash" text NOT NULL,
    "deviceId" text NOT NULL,
    "issuedAt" timestamp without time zone NOT NULL,
    "idleExpiresAt" timestamp without time zone NOT NULL,
    "absoluteExpiresAt" timestamp without time zone NOT NULL,
    "rotatedAt" timestamp without time zone,
    "revokedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "acs_refresh_tokens_hash_key" ON "acs_refresh_tokens" USING btree ("tokenHash");
CREATE INDEX "acs_refresh_tokens_family_idx" ON "acs_refresh_tokens" USING btree ("familyId");
CREATE INDEX "acs_refresh_tokens_user_idx" ON "acs_refresh_tokens" USING btree ("userId");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "acs_refresh_tokens"
    ADD CONSTRAINT "acs_refresh_tokens_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261003151950052', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261003151950052', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
