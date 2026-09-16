BEGIN;

--
-- ACTION DROP TABLE
--
DROP TABLE "audit_logs" CASCADE;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "audit_logs" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "actionType" text NOT NULL,
    "resourceType" text NOT NULL,
    "resourceId" uuid,
    "timestamp" timestamp without time zone NOT NULL,
    "ipHash" text NOT NULL,
    "result" text NOT NULL,
    "sequence" bigint NOT NULL,
    "previousHash" text NOT NULL,
    "entryHash" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "audit_logs_sequence_idx" ON "audit_logs" USING btree ("sequence");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "audit_logs"
    ADD CONSTRAINT "audit_logs_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260914154730381', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260914154730381', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
