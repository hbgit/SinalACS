-- Seed de desenvolvimento. Somente dados sintéticos — nunca dados reais de
-- paciente (LGPD).
--
-- Os UUIDs são fixos porque o dev-login os referencia diretamente.
--
-- Diferenças em relação ao seed do backend dart:io:
--   * Colunas em camelCase citada, convenção do ORM do Serverpod.
--   * patients e acs não têm mais coluna userId: o id da linha É o UUID do
--     usuário, o que preserva a semântica de patient_id e recupera as FKs.

INSERT INTO "ubs" ("id", "name", "address", "city", "state")
VALUES ('00000000-0000-4000-8000-000000000004', 'UBS Desenvolvimento', 'Endereço local', 'São Paulo', 'SP')
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "micro_areas" ("id", "name", "ubsId", "geoJsonBoundary")
VALUES ('00000000-0000-4000-8000-000000000003', 'Microárea 12', '00000000-0000-4000-8000-000000000004', '{}')
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "users" ("id", "cpfHash", "name", "birthDate", "role", "microAreaId", "createdAt", "updatedAt")
VALUES
  ('00000000-0000-4000-8000-000000000001', 'development-patient', 'Paciente de desenvolvimento', '1990-01-01', 'patient', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  ('00000000-0000-4000-8000-000000000002', 'development-acs', 'ACS de desenvolvimento', '1980-01-01', 'acs', '00000000-0000-4000-8000-000000000003', NOW(), NOW())
ON CONFLICT ("id") DO NOTHING;

-- id = UUID do usuário paciente.
INSERT INTO "patients" ("id", "emergencyContact", "isChronic", "chronicConditions")
VALUES ('00000000-0000-4000-8000-000000000001', 'Contato de desenvolvimento', false, '[]')
ON CONFLICT ("id") DO NOTHING;

-- id = UUID do usuário ACS.
INSERT INTO "acs" ("id", "enrollmentId", "ubsId", "active")
VALUES ('00000000-0000-4000-8000-000000000002', 'ACS-001', '00000000-0000-4000-8000-000000000004', true)
ON CONFLICT ("id") DO NOTHING;
