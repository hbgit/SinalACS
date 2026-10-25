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
