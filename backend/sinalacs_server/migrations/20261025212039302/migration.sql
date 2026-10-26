BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "telemetry_events" (
    "id" bigserial PRIMARY KEY,
    "eventId" uuid NOT NULL,
    "eventName" text NOT NULL,
    "schemaVersion" bigint NOT NULL DEFAULT 1,
    "source" text NOT NULL,
    "occurredAt" timestamp without time zone NOT NULL,
    "receivedAt" timestamp without time zone NOT NULL,
    "clockSkewMs" bigint,
    "actorId" uuid,
    "devicePseudonym" text,
    "patientPseudonym" text,
    "alertId" uuid,
    "appVersion" text NOT NULL,
    "payload" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "telemetry_events_event_id_key" ON "telemetry_events" USING btree ("eventId");
CREATE INDEX "telemetry_events_name_occurred_idx" ON "telemetry_events" USING btree ("eventName", "occurredAt");
CREATE INDEX "telemetry_events_alert_idx" ON "telemetry_events" USING btree ("alertId");
CREATE INDEX "telemetry_events_patient_idx" ON "telemetry_events" USING btree ("patientPseudonym");
CREATE INDEX "telemetry_events_received_idx" ON "telemetry_events" USING btree ("receivedAt");


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261025212039302', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261025212039302', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
