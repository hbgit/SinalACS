BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "device_certificates" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "userId" uuid NOT NULL,
    "deviceId" text NOT NULL,
    "microAreaId" uuid NOT NULL,
    "serial" text NOT NULL,
    "fingerprintSha256" text NOT NULL,
    "notBefore" timestamp without time zone NOT NULL,
    "notAfter" timestamp without time zone NOT NULL,
    "issuedAt" timestamp without time zone NOT NULL,
    "revokedAt" timestamp without time zone,
    "revocationReason" text
);

-- Indexes
CREATE INDEX "device_certificates_device_idx" ON "device_certificates" USING btree ("deviceId");
CREATE INDEX "device_certificates_user_idx" ON "device_certificates" USING btree ("userId");
CREATE UNIQUE INDEX "device_certificates_serial_key" ON "device_certificates" USING btree ("serial");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "device_crl_counters" (
    "id" bigserial PRIMARY KEY,
    "lastNumber" bigint NOT NULL
);

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "device_certificates"
    ADD CONSTRAINT "device_certificates_fk_0"
    FOREIGN KEY("userId")
    REFERENCES "users"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261028025257928', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261028025257928', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
