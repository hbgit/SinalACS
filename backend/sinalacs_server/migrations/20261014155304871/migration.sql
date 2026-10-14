BEGIN;

--
-- ACTION CREATE TABLE
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
-- ACTION CREATE FOREIGN KEY
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
-- MIGRATION VERSION FOR sinalacs
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('sinalacs', '20261014155304871', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20261014155304871', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260129180959368', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260129180959368', "timestamp" = now();


COMMIT;
