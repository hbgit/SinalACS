BEGIN;

--
-- Class Acs as table acs
--
CREATE TABLE "acs" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "enrollmentId" text NOT NULL,
    "ubsId" uuid NOT NULL,
    "active" boolean NOT NULL,
    "lastSyncAt" timestamp without time zone
);

-- Indexes
CREATE INDEX "acs_ubs_idx" ON "acs" USING btree ("ubsId");

--
-- Class AlertDeliveryRecord as table alert_deliveries
--
CREATE TABLE "alert_deliveries" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "alertId" uuid NOT NULL,
    "acsId" uuid NOT NULL,
    "acknowledgedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "alert_deliveries_alert_acs_key" ON "alert_deliveries" USING btree ("alertId", "acsId");

--
-- Class AlertIdempotencyKey as table alert_idempotency_keys
--
CREATE TABLE "alert_idempotency_keys" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "key" text NOT NULL,
    "alertId" uuid NOT NULL,
    "locationHash" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "alert_idempotency_keys_key_key" ON "alert_idempotency_keys" USING btree ("key");

--
-- Class Alert as table alerts
--
CREATE TABLE "alerts" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "patientId" uuid NOT NULL,
    "acsId" uuid,
    "microAreaId" uuid,
    "triggeredAt" timestamp without time zone NOT NULL,
    "receivedAt" timestamp without time zone,
    "respondedAt" timestamp without time zone,
    "acknowledgedAt" timestamp without time zone,
    "riskLevel" text NOT NULL,
    "locationHash" text NOT NULL,
    "status" text NOT NULL,
    "mqttTopic" text NOT NULL,
    "deviceId" text NOT NULL,
    "retryCount" bigint NOT NULL,
    "version" bigint NOT NULL
);

-- Indexes
CREATE INDEX "alerts_micro_area_status_idx" ON "alerts" USING btree ("microAreaId", "status", "triggeredAt");

--
-- Class AuditLog as table audit_logs
--
CREATE TABLE "audit_logs" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "actionType" text NOT NULL,
    "resourceType" text NOT NULL,
    "resourceId" uuid,
    "timestamp" timestamp without time zone NOT NULL,
    "ipHash" text NOT NULL,
    "result" text NOT NULL
);

--
-- Class ConsentLog as table consent_logs
--
CREATE TABLE "consent_logs" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "purpose" text NOT NULL,
    "action" text NOT NULL,
    "version" text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "ipHash" text NOT NULL,
    "userAgent" text NOT NULL,
    "signature" text NOT NULL
);

--
-- Class MicroArea as table micro_areas
--
CREATE TABLE "micro_areas" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "name" text NOT NULL,
    "ubsId" uuid NOT NULL,
    "geoJsonBoundary" text NOT NULL
);

-- Indexes
CREATE INDEX "micro_areas_ubs_idx" ON "micro_areas" USING btree ("ubsId");

--
-- Class Patient as table patients
--
CREATE TABLE "patients" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "emergencyContact" text NOT NULL,
    "isChronic" boolean NOT NULL,
    "chronicConditions" json NOT NULL,
    "lastLocationHash" text,
    "lastTriageAt" timestamp without time zone
);

--
-- Class TriageSession as table triage_sessions
--
CREATE TABLE "triage_sessions" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "patientId" uuid NOT NULL,
    "answers" json NOT NULL,
    "resultRisk" text NOT NULL,
    "resultDisplay" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "deviceId" text NOT NULL
);

--
-- Class Ubs as table ubs
--
CREATE TABLE "ubs" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "name" text NOT NULL,
    "address" text NOT NULL,
    "city" text NOT NULL,
    "state" text NOT NULL
);

--
-- Class User as table users
--
CREATE TABLE "users" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "cpfHash" text NOT NULL,
    "name" text NOT NULL,
    "birthDate" timestamp without time zone NOT NULL,
    "role" text NOT NULL,
    "microAreaId" uuid,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE INDEX "users_cpf_hash_idx" ON "users" USING btree ("cpfHash");
CREATE INDEX "users_micro_area_idx" ON "users" USING btree ("microAreaId");

--
-- Class Visit as table visits
--
CREATE TABLE "visits" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "patientId" uuid NOT NULL,
    "acsId" uuid NOT NULL,
    "scheduledAt" timestamp without time zone NOT NULL,
    "startedAt" timestamp without time zone,
    "completedAt" timestamp without time zone,
    "status" text NOT NULL,
    "riskLevelBefore" text NOT NULL,
    "riskLevelAfter" text,
    "notes" json NOT NULL,
    "syncStatus" text NOT NULL,
    "localId" uuid NOT NULL,
    "syncAt" timestamp without time zone,
    "version" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "visits_local_id_key" ON "visits" USING btree ("localId");

--
-- Class CloudStorageEntry as table serverpod_cloud_storage
--
CREATE TABLE "serverpod_cloud_storage" (
    "id" bigserial PRIMARY KEY,
    "storageId" text NOT NULL,
    "path" text NOT NULL,
    "addedTime" timestamp without time zone NOT NULL,
    "expiration" timestamp without time zone,
    "byteData" bytea NOT NULL,
    "verified" boolean NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_path_idx" ON "serverpod_cloud_storage" USING btree ("storageId", "path");
CREATE INDEX "serverpod_cloud_storage_expiration" ON "serverpod_cloud_storage" USING btree ("expiration");

--
-- Class CloudStorageDirectUploadEntry as table serverpod_cloud_storage_direct_upload
--
CREATE TABLE "serverpod_cloud_storage_direct_upload" (
    "id" bigserial PRIMARY KEY,
    "storageId" text NOT NULL,
    "path" text NOT NULL,
    "expiration" timestamp without time zone NOT NULL,
    "authKey" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_direct_upload_storage_path" ON "serverpod_cloud_storage_direct_upload" USING btree ("storageId", "path");

--
-- Class FutureCallEntry as table serverpod_future_call
--
CREATE TABLE "serverpod_future_call" (
    "id" bigserial PRIMARY KEY,
    "name" text NOT NULL,
    "time" timestamp without time zone NOT NULL,
    "serializedObject" text,
    "serverId" text NOT NULL,
    "identifier" text
);

-- Indexes
CREATE INDEX "serverpod_future_call_time_idx" ON "serverpod_future_call" USING btree ("time");
CREATE INDEX "serverpod_future_call_serverId_idx" ON "serverpod_future_call" USING btree ("serverId");
CREATE INDEX "serverpod_future_call_identifier_idx" ON "serverpod_future_call" USING btree ("identifier");

--
-- Class ServerHealthConnectionInfo as table serverpod_health_connection_info
--
CREATE TABLE "serverpod_health_connection_info" (
    "id" bigserial PRIMARY KEY,
    "serverId" text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "active" bigint NOT NULL,
    "closing" bigint NOT NULL,
    "idle" bigint NOT NULL,
    "granularity" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_health_connection_info_timestamp_idx" ON "serverpod_health_connection_info" USING btree ("timestamp", "serverId", "granularity");

--
-- Class ServerHealthMetric as table serverpod_health_metric
--
CREATE TABLE "serverpod_health_metric" (
    "id" bigserial PRIMARY KEY,
    "name" text NOT NULL,
    "serverId" text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "isHealthy" boolean NOT NULL,
    "value" double precision NOT NULL,
    "granularity" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_health_metric_timestamp_idx" ON "serverpod_health_metric" USING btree ("timestamp", "serverId", "name", "granularity");

--
-- Class LogEntry as table serverpod_log
--
CREATE TABLE "serverpod_log" (
    "id" bigserial PRIMARY KEY,
    "sessionLogId" bigint NOT NULL,
    "messageId" bigint,
    "reference" text,
    "serverId" text NOT NULL,
    "time" timestamp without time zone NOT NULL,
    "logLevel" bigint NOT NULL,
    "message" text NOT NULL,
    "error" text,
    "stackTrace" text,
    "order" bigint NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_log_sessionLogId_idx" ON "serverpod_log" USING btree ("sessionLogId");

--
-- Class MessageLogEntry as table serverpod_message_log
--
CREATE TABLE "serverpod_message_log" (
    "id" bigserial PRIMARY KEY,
    "sessionLogId" bigint NOT NULL,
    "serverId" text NOT NULL,
    "messageId" bigint NOT NULL,
    "endpoint" text NOT NULL,
    "messageName" text NOT NULL,
    "duration" double precision NOT NULL,
    "error" text,
    "stackTrace" text,
    "slow" boolean NOT NULL,
    "order" bigint NOT NULL
);

--
-- Class MethodInfo as table serverpod_method
--
CREATE TABLE "serverpod_method" (
    "id" bigserial PRIMARY KEY,
    "endpoint" text NOT NULL,
    "method" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_method_endpoint_method_idx" ON "serverpod_method" USING btree ("endpoint", "method");

--
-- Class DatabaseMigrationVersion as table serverpod_migrations
--
CREATE TABLE "serverpod_migrations" (
    "id" bigserial PRIMARY KEY,
    "module" text NOT NULL,
    "version" text NOT NULL,
    "timestamp" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_migrations_ids" ON "serverpod_migrations" USING btree ("module");

--
-- Class QueryLogEntry as table serverpod_query_log
--
CREATE TABLE "serverpod_query_log" (
    "id" bigserial PRIMARY KEY,
    "serverId" text NOT NULL,
    "sessionLogId" bigint NOT NULL,
    "messageId" bigint,
    "query" text NOT NULL,
    "duration" double precision NOT NULL,
    "numRows" bigint,
    "error" text,
    "stackTrace" text,
    "slow" boolean NOT NULL,
    "order" bigint NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_query_log_sessionLogId_idx" ON "serverpod_query_log" USING btree ("sessionLogId");

--
-- Class ReadWriteTestEntry as table serverpod_readwrite_test
--
CREATE TABLE "serverpod_readwrite_test" (
    "id" bigserial PRIMARY KEY,
    "number" bigint NOT NULL
);

--
-- Class RuntimeSettings as table serverpod_runtime_settings
--
CREATE TABLE "serverpod_runtime_settings" (
    "id" bigserial PRIMARY KEY,
    "logSettings" json NOT NULL,
    "logSettingsOverrides" json NOT NULL,
    "logServiceCalls" boolean NOT NULL,
    "logMalformedCalls" boolean NOT NULL
);

--
-- Class SessionLogEntry as table serverpod_session_log
--
CREATE TABLE "serverpod_session_log" (
    "id" bigserial PRIMARY KEY,
    "serverId" text NOT NULL,
    "time" timestamp without time zone NOT NULL,
    "module" text,
    "endpoint" text,
    "method" text,
    "duration" double precision,
    "numQueries" bigint,
    "slow" boolean,
    "error" text,
    "stackTrace" text,
    "authenticatedUserId" bigint,
    "userId" text,
    "isOpen" boolean,
    "touched" timestamp without time zone NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_session_log_serverid_idx" ON "serverpod_session_log" USING btree ("serverId");
CREATE INDEX "serverpod_session_log_time_idx" ON "serverpod_session_log" USING btree ("time");
CREATE INDEX "serverpod_session_log_touched_idx" ON "serverpod_session_log" USING btree ("touched");
CREATE INDEX "serverpod_session_log_isopen_idx" ON "serverpod_session_log" USING btree ("isOpen");

--
-- Foreign relations for "alert_deliveries" table
--
ALTER TABLE ONLY "alert_deliveries"
    ADD CONSTRAINT "alert_deliveries_fk_0"
    FOREIGN KEY("alertId")
    REFERENCES "alerts"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "alert_deliveries"
    ADD CONSTRAINT "alert_deliveries_fk_1"
    FOREIGN KEY("acsId")
    REFERENCES "acs"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "alert_idempotency_keys" table
--
ALTER TABLE ONLY "alert_idempotency_keys"
    ADD CONSTRAINT "alert_idempotency_keys_fk_0"
    FOREIGN KEY("alertId")
    REFERENCES "alerts"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "alerts" table
--
ALTER TABLE ONLY "alerts"
    ADD CONSTRAINT "alerts_fk_0"
    FOREIGN KEY("patientId")
    REFERENCES "patients"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "alerts"
    ADD CONSTRAINT "alerts_fk_1"
    FOREIGN KEY("acsId")
    REFERENCES "acs"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "audit_logs" table
--
ALTER TABLE ONLY "audit_logs"
    ADD CONSTRAINT "audit_logs_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "consent_logs" table
--
ALTER TABLE ONLY "consent_logs"
    ADD CONSTRAINT "consent_logs_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "triage_sessions" table
--
ALTER TABLE ONLY "triage_sessions"
    ADD CONSTRAINT "triage_sessions_fk_0"
    FOREIGN KEY("patientId")
    REFERENCES "patients"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "visits" table
--
ALTER TABLE ONLY "visits"
    ADD CONSTRAINT "visits_fk_0"
    FOREIGN KEY("patientId")
    REFERENCES "patients"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "visits"
    ADD CONSTRAINT "visits_fk_1"
    FOREIGN KEY("acsId")
    REFERENCES "acs"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_log" table
--
ALTER TABLE ONLY "serverpod_log"
    ADD CONSTRAINT "serverpod_log_fk_0"
    FOREIGN KEY("sessionLogId")
    REFERENCES "serverpod_session_log"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_message_log" table
--
ALTER TABLE ONLY "serverpod_message_log"
    ADD CONSTRAINT "serverpod_message_log_fk_0"
    FOREIGN KEY("sessionLogId")
    REFERENCES "serverpod_session_log"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_query_log" table
--
ALTER TABLE ONLY "serverpod_query_log"
    ADD CONSTRAINT "serverpod_query_log_fk_0"
    FOREIGN KEY("sessionLogId")
    REFERENCES "serverpod_session_log"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20260909011754405', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260909011754405', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
