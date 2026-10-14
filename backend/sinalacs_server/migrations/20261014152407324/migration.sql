BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "scheduled_notices" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "createdBy" uuid NOT NULL,
    "microAreaId" uuid NOT NULL,
    "audience" text NOT NULL,
    "title" text NOT NULL,
    "message" text NOT NULL,
    "scheduledFor" timestamp without time zone NOT NULL,
    "status" text NOT NULL,
    "recipients" bigint,
    "accepted" bigint,
    "failureReason" text,
    "createdAt" timestamp without time zone NOT NULL,
    "sentAt" timestamp without time zone
);

-- Indexes
CREATE INDEX "scheduled_notices_due_idx" ON "scheduled_notices" USING btree ("status", "scheduledFor");
CREATE INDEX "scheduled_notices_area_idx" ON "scheduled_notices" USING btree ("microAreaId", "createdAt");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "scheduled_notices"
    ADD CONSTRAINT "scheduled_notices_fk_0"
    FOREIGN KEY("createdBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "scheduled_notices"
    ADD CONSTRAINT "scheduled_notices_fk_1"
    FOREIGN KEY("microAreaId")
    REFERENCES "micro_areas"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261014152407324', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261014152407324', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
