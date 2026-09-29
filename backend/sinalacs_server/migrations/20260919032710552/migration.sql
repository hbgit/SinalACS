BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "otp_challenges" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "codeHash" text NOT NULL,
    "attempts" bigint NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    "consumedAt" timestamp without time zone
);

-- Indexes
CREATE INDEX "otp_challenges_user_id_created_at_idx" ON "otp_challenges" USING btree ("userId", "createdAt");

--
-- ACTION ALTER TABLE
--
DROP INDEX "users_cpf_hash_idx";
CREATE UNIQUE INDEX "users_cpf_hash_key" ON "users" USING btree ("cpfHash");
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "otp_challenges"
    ADD CONSTRAINT "otp_challenges_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260919032710552', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260919032710552', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
