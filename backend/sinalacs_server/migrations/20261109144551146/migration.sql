BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "patient_device_credentials" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "patientId" uuid NOT NULL,
    "deviceId" text NOT NULL,
    "credentialHash" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "lastUsedAt" timestamp without time zone,
    "revokedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "patient_device_credentials_device_id_key" ON "patient_device_credentials" USING btree ("deviceId");
CREATE INDEX "patient_device_credentials_patient_id_idx" ON "patient_device_credentials" USING btree ("patientId");

--
-- ACTION ALTER TABLE
--
ALTER TABLE "users" ALTER COLUMN "cpfHash" DROP NOT NULL;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "patient_device_credentials"
    ADD CONSTRAINT "patient_device_credentials_fk_0"
    FOREIGN KEY("patientId")
    REFERENCES "patients"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261109144551146', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261109144551146', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
