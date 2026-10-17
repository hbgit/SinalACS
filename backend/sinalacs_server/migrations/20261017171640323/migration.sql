BEGIN;

--
-- ACTION CREATE TABLE
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
-- ACTION CREATE FOREIGN KEY
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
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261017171640323', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261017171640323', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
