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
CREATE UNIQUE INDEX "acs_enrollment_id_key" ON "acs" USING btree ("enrollmentId");

--
-- Class AcsRefreshToken as table acs_refresh_tokens
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
-- Class AcsUploadToken as table acs_upload_tokens
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
-- Class AlertOutboxEntry as table alert_outbox
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
    "resolvedAt" timestamp without time zone,
    "riskLevel" text NOT NULL,
    "locationHash" text NOT NULL,
    "locationCell" text,
    "status" text NOT NULL,
    "mqttTopic" text NOT NULL,
    "deviceId" text NOT NULL,
    "retryCount" bigint NOT NULL,
    "version" bigint NOT NULL,
    "escalatedAt" timestamp without time zone,
    "escalatedBy" uuid,
    "escalationReason" text
);

-- Indexes
CREATE INDEX "alerts_micro_area_status_idx" ON "alerts" USING btree ("microAreaId", "status", "triggeredAt");

--
-- Class AuditChainCheckpoint as table audit_chain_checkpoints
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
-- Class AuditExport as table audit_exports
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
    "result" text NOT NULL,
    "sequence" bigint NOT NULL,
    "previousHash" text NOT NULL,
    "entryHash" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "audit_logs_sequence_idx" ON "audit_logs" USING btree ("sequence");
CREATE INDEX "audit_logs_timestamp_idx" ON "audit_logs" USING btree ("timestamp");
CREATE INDEX "audit_logs_user_sequence_idx" ON "audit_logs" USING btree ("userId", "sequence");

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
-- Class DataSubjectRequest as table data_subject_requests
--
CREATE TABLE "data_subject_requests" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "requestType" text NOT NULL,
    "detailsEncrypted" text NOT NULL,
    "detailsKeyVersion" bigint NOT NULL,
    "status" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "dueAt" timestamp without time zone NOT NULL,
    "decidedAt" timestamp without time zone,
    "decidedBy" uuid,
    "resolutionEncrypted" text,
    "resolutionKeyVersion" bigint
);

-- Indexes
CREATE INDEX "data_subject_requests_user_id_type_idx" ON "data_subject_requests" USING btree ("userId", "requestType");

--
-- Class DeviceWipeOrder as table device_wipe_orders
--
CREATE TABLE "device_wipe_orders" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "deviceId" text NOT NULL,
    "targetUserId" uuid NOT NULL,
    "requestedBy" uuid NOT NULL,
    "reason" text NOT NULL,
    "requestedAt" timestamp without time zone NOT NULL,
    "deliveredAt" timestamp without time zone,
    "confirmedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "device_wipe_orders_device_key" ON "device_wipe_orders" USING btree ("deviceId");

--
-- Class EnrollmentToken as table enrollment_tokens
--
CREATE TABLE "enrollment_tokens" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "tokenHash" text NOT NULL,
    "patientId" uuid NOT NULL,
    "microAreaId" uuid NOT NULL,
    "createdByAcsId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "expiresAt" timestamp without time zone NOT NULL,
    "consumedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "enrollment_tokens_token_hash_key" ON "enrollment_tokens" USING btree ("tokenHash");

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
-- Class OtpChallenge as table otp_challenges
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
-- Class Patient as table patients
--
CREATE TABLE "patients" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "emergencyContactEncrypted" text NOT NULL DEFAULT ''::text,
    "emergencyContactKeyVersion" bigint NOT NULL DEFAULT 1,
    "isChronic" boolean NOT NULL,
    "chronicConditionsEncrypted" text NOT NULL DEFAULT ''::text,
    "chronicConditionsKeyVersion" bigint NOT NULL DEFAULT 1,
    "lastLocationHash" text,
    "lastTriageAt" timestamp without time zone
);

--
-- Class PushToken as table push_tokens
--
CREATE TABLE "push_tokens" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "microAreaId" uuid,
    "token" text NOT NULL,
    "platform" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "push_tokens_token_key" ON "push_tokens" USING btree ("token");
CREATE INDEX "push_tokens_user_id_idx" ON "push_tokens" USING btree ("userId");

--
-- Class ScheduledNotice as table scheduled_notices
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
-- Class StaffAccount as table staff_accounts
--
CREATE TABLE "staff_accounts" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "enrollmentId" text NOT NULL,
    "active" boolean NOT NULL,
    "ubsId" uuid,
    "activationCodeHash" text,
    "activationCodeExpiresAt" timestamp without time zone,
    "activationCodeIssuedBy" text,
    "activationCodeIssuedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "staff_accounts_enrollment_id_key" ON "staff_accounts" USING btree ("enrollmentId");

--
-- Class TermsVersion as table terms_versions
--
CREATE TABLE "terms_versions" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "version" text NOT NULL,
    "summary" text NOT NULL,
    "effectiveFrom" timestamp without time zone NOT NULL,
    "createdBy" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "legallyReviewedAt" timestamp without time zone,
    "legallyReviewedBy" uuid,
    "publishedAt" timestamp without time zone,
    "publishedBy" uuid
);

-- Indexes
CREATE UNIQUE INDEX "terms_versions_version_key" ON "terms_versions" USING btree ("version");

--
-- Class TriageSession as table triage_sessions
--
CREATE TABLE "triage_sessions" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "patientId" uuid NOT NULL,
    "answersEncrypted" text NOT NULL DEFAULT ''::text,
    "answersKeyVersion" bigint NOT NULL DEFAULT 1,
    "resultRiskEncrypted" text NOT NULL DEFAULT ''::text,
    "resultRiskKeyVersion" bigint NOT NULL DEFAULT 1,
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
    "state" text NOT NULL,
    "contactPhone" text
);

--
-- Class UserCredential as table user_credentials
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
    "lockStreak" bigint NOT NULL DEFAULT 0,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL,
    "totpSecretEncrypted" text,
    "totpKeyVersion" bigint,
    "totpEnabledAt" timestamp without time zone,
    "totpLastStep" bigint
);

-- Indexes
CREATE UNIQUE INDEX "user_credentials_user_id_key" ON "user_credentials" USING btree ("userId");

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
CREATE UNIQUE INDEX "users_cpf_hash_key" ON "users" USING btree ("cpfHash");
CREATE INDEX "users_micro_area_idx" ON "users" USING btree ("microAreaId");

--
-- Class Visit as table visits
--
CREATE TABLE "visits" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "patientId" uuid NOT NULL,
    "acsId" uuid,
    "authorship" text NOT NULL DEFAULT 'acs'::text,
    "originDeviceId" text,
    "scheduledAt" timestamp without time zone NOT NULL,
    "startedAt" timestamp without time zone,
    "completedAt" timestamp without time zone,
    "status" text NOT NULL,
    "riskLevelBeforeEncrypted" text NOT NULL DEFAULT ''::text,
    "riskLevelBeforeKeyVersion" bigint NOT NULL DEFAULT 1,
    "riskLevelAfterEncrypted" text NOT NULL DEFAULT ''::text,
    "riskLevelAfterKeyVersion" bigint NOT NULL DEFAULT 1,
    "notesEncrypted" text NOT NULL DEFAULT ''::text,
    "notesKeyVersion" bigint NOT NULL DEFAULT 1,
    "syncStatus" text NOT NULL,
    "arrivalMethod" text NOT NULL DEFAULT 'manual'::text,
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
-- Foreign relations for "acs_refresh_tokens" table
--
ALTER TABLE ONLY "acs_refresh_tokens"
    ADD CONSTRAINT "acs_refresh_tokens_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "acs_upload_tokens" table
--
ALTER TABLE ONLY "acs_upload_tokens"
    ADD CONSTRAINT "acs_upload_tokens_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

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
-- Foreign relations for "alert_outbox" table
--
ALTER TABLE ONLY "alert_outbox"
    ADD CONSTRAINT "alert_outbox_fk_0"
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
-- Foreign relations for "audit_exports" table
--
ALTER TABLE ONLY "audit_exports"
    ADD CONSTRAINT "audit_exports_fk_0"
    FOREIGN KEY("requestedBy")
    REFERENCES "users"("id")
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
-- Foreign relations for "data_subject_requests" table
--
ALTER TABLE ONLY "data_subject_requests"
    ADD CONSTRAINT "data_subject_requests_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "data_subject_requests"
    ADD CONSTRAINT "data_subject_requests_fk_1"
    FOREIGN KEY("decidedBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "device_wipe_orders" table
--
ALTER TABLE ONLY "device_wipe_orders"
    ADD CONSTRAINT "device_wipe_orders_fk_0"
    FOREIGN KEY("targetUserId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "device_wipe_orders"
    ADD CONSTRAINT "device_wipe_orders_fk_1"
    FOREIGN KEY("requestedBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "enrollment_tokens" table
--
ALTER TABLE ONLY "enrollment_tokens"
    ADD CONSTRAINT "enrollment_tokens_fk_0"
    FOREIGN KEY("patientId")
    REFERENCES "patients"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "enrollment_tokens"
    ADD CONSTRAINT "enrollment_tokens_fk_1"
    FOREIGN KEY("createdByAcsId")
    REFERENCES "acs"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "otp_challenges" table
--
ALTER TABLE ONLY "otp_challenges"
    ADD CONSTRAINT "otp_challenges_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "push_tokens" table
--
ALTER TABLE ONLY "push_tokens"
    ADD CONSTRAINT "push_tokens_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "scheduled_notices" table
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
-- Foreign relations for "terms_versions" table
--
ALTER TABLE ONLY "terms_versions"
    ADD CONSTRAINT "terms_versions_fk_0"
    FOREIGN KEY("createdBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "terms_versions"
    ADD CONSTRAINT "terms_versions_fk_1"
    FOREIGN KEY("legallyReviewedBy")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "terms_versions"
    ADD CONSTRAINT "terms_versions_fk_2"
    FOREIGN KEY("publishedBy")
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
-- Foreign relations for "user_credentials" table
--
ALTER TABLE ONLY "user_credentials"
    ADD CONSTRAINT "user_credentials_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
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
-- APPEND-ONLY DA TRILHA DE AUDITORIA (#82, RF17/STRIDE-R)
-- Fonte: database/audit_append_only.sql. O Serverpod reescreve o
-- definition.sql a cada create-migration: rode
-- scripts/dev/append_audit_append_only.sh depois de toda migração nova
-- (backend/CLAUDE.md). Limite: superusuário e dono da tabela ainda contornam
-- (session_replication_role = replica, ALTER TABLE ... DISABLE TRIGGER).
--
CREATE OR REPLACE FUNCTION "sinalacs_audit_append_only"() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'tabela de auditoria % é append-only: % recusado',
        TG_TABLE_NAME, TG_OP
        USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS "audit_logs_append_only" ON "audit_logs";
CREATE TRIGGER "audit_logs_append_only"
    BEFORE UPDATE OR DELETE OR TRUNCATE ON "audit_logs"
    FOR EACH STATEMENT EXECUTE FUNCTION "sinalacs_audit_append_only"();

DROP TRIGGER IF EXISTS "audit_exports_append_only" ON "audit_exports";
CREATE TRIGGER "audit_exports_append_only"
    BEFORE UPDATE OR DELETE OR TRUNCATE ON "audit_exports"
    FOR EACH STATEMENT EXECUTE FUNCTION "sinalacs_audit_append_only"();

DROP TRIGGER IF EXISTS "audit_chain_checkpoints_append_only" ON "audit_chain_checkpoints";
CREATE TRIGGER "audit_chain_checkpoints_append_only"
    BEFORE UPDATE OR DELETE OR TRUNCATE ON "audit_chain_checkpoints"
    FOR EACH STATEMENT EXECUTE FUNCTION "sinalacs_audit_append_only"();

REVOKE UPDATE, DELETE, TRUNCATE
    ON "audit_logs", "audit_exports", "audit_chain_checkpoints"
    FROM PUBLIC;

--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261025201950984', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261025201950984', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
