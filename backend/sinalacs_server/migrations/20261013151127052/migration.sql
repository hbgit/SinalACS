BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "audit_chain_checkpoints" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "sequence" bigint NOT NULL,
    "entryHash" text NOT NULL,
    "signature" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "audit_chain_checkpoints_sequence_idx" ON "audit_chain_checkpoints" USING btree ("sequence");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "audit_exports" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "requestedBy" uuid NOT NULL,
    "requestedAt" timestamp without time zone NOT NULL,
    "filtersJson" text NOT NULL,
    "format" text NOT NULL,
    "rowCount" bigint NOT NULL,
    "firstSequence" bigint,
    "lastSequence" bigint,
    "contentSha256" text NOT NULL,
    "chainState" text NOT NULL
);

-- Indexes
CREATE INDEX "audit_exports_requested_at_idx" ON "audit_exports" USING btree ("requestedAt");

--
-- ACTION ALTER TABLE
--
CREATE INDEX "audit_logs_timestamp_idx" ON "audit_logs" USING btree ("timestamp");
CREATE INDEX "audit_logs_user_sequence_idx" ON "audit_logs" USING btree ("userId", "sequence");
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "audit_exports"
    ADD CONSTRAINT "audit_exports_fk_0"
    FOREIGN KEY("requestedBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261013151127052', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261013151127052', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
