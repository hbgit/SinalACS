BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "alert_outbox" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "alertId" uuid NOT NULL,
    "topic" text NOT NULL,
    "payload" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "publishedAt" timestamp without time zone,
    "attempts" bigint NOT NULL,
    "nextAttemptAt" timestamp without time zone NOT NULL,
    "lastError" text
);

-- Indexes
CREATE INDEX "alert_outbox_pending_idx" ON "alert_outbox" USING btree ("publishedAt", "nextAttemptAt");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "alert_outbox"
    ADD CONSTRAINT "alert_outbox_fk_0"
    FOREIGN KEY("alertId")
    REFERENCES "alerts"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260909155542184', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260909155542184', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
