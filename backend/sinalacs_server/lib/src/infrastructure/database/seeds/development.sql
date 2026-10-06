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

-- Telefone sintético (RF13). O UPDATE cobre bancos de dev criados antes da coluna.
UPDATE "ubs" SET "contactPhone" = '+55 11 5550-0100'
WHERE "id" = '00000000-0000-4000-8000-000000000004' AND "contactPhone" IS NULL;

INSERT INTO "micro_areas" ("id", "name", "ubsId", "geoJsonBoundary")
VALUES ('00000000-0000-4000-8000-000000000003', 'Microárea 12', '00000000-0000-4000-8000-000000000004', '{}')
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "users" ("id", "cpfHash", "name", "birthDate", "role", "microAreaId", "createdAt", "updatedAt")
VALUES
  ('00000000-0000-4000-8000-000000000001', 'development-patient', 'Paciente de desenvolvimento', '1990-01-01', 'patient', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  ('00000000-0000-4000-8000-000000000002', 'development-acs', 'ACS de desenvolvimento', '1980-01-01', 'acs', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  -- Pacientes sintéticos adicionais, só para o seletor da visita de rotina ter
  -- de onde escolher. Nomes obviamente fictícios (regra do repositório: nunca
  -- dado real em seed/teste/log).
  ('00000000-0000-4000-8000-000000000005', 'development-patient-05', 'Fulano de Tal', '1975-03-10', 'patient', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  ('00000000-0000-4000-8000-000000000006', 'development-patient-06', 'Ciclana da Silva', '1988-07-22', 'patient', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  ('00000000-0000-4000-8000-000000000007', 'development-patient-07', 'Beltrano de Souza', '1962-11-30', 'patient', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  ('00000000-0000-4000-8000-000000000008', 'development-patient-08', 'Sicrana Pereira', '1999-05-14', 'patient', '00000000-0000-4000-8000-000000000003', NOW(), NOW()),
  -- Fora da microárea do seed: prova de que o diretório e o sync recusam
  -- território alheio, sem precisar de outra stack de teste.
  ('00000000-0000-4000-8000-000000000009', 'development-patient-09', 'Paciente de Outra Área', '1970-01-01', 'patient', '00000000-0000-4000-8000-000000000099', NOW(), NOW()),
  -- Admin do backoffice (issue #39): papel `admin`, sem microárea. O `cpfHash` é
  -- um literal único que nenhum HMAC produz: ele entra por matrícula + senha +
  -- TOTP (`auth.loginStaff`), nunca por CPF, e o `cpf-hash-seed` só faz UPDATE
  -- nas linhas de paciente que lista, então não o toca. A senha vem de
  -- DEV_ADMIN_PASSWORD (`seed_acs_credentials`). Sem TOTP semeado: a MFA do
  -- staff é obrigatória e o primeiro acesso passa pela tela de ativação.
  ('00000000-0000-4000-8000-000000000090', 'development-admin', 'Admin de desenvolvimento', '1985-01-01', 'admin', NULL, NOW(), NOW())
ON CONFLICT ("id") DO NOTHING;

-- id = UUID do usuário paciente.
--
-- `chronicConditions` virou `chronicConditionsEncrypted` (AES-256-GCM, RNF03 /
-- INV-04). Este arquivo roda por `psql`, FORA do processo Dart, então não tem
-- como chamar HealthDataCipher — as linhas entram com ciphertext vazio (que o
-- store lê como "sem condições") e `bin/seed_health_data.dart` as completa
-- logo depois, no serviço `health-data-seed` do docker-compose.yml. Colar um
-- ciphertext literal aqui seria a alternativa, mas duplicaria a lógica de
-- cifragem fora do Dart e quebraria em silêncio a cada troca de chave.
INSERT INTO "patients" ("id", "emergencyContact", "isChronic", "chronicConditionsEncrypted", "chronicConditionsKeyVersion")
VALUES
  ('00000000-0000-4000-8000-000000000001', 'Contato de desenvolvimento', false, '', 1),
  ('00000000-0000-4000-8000-000000000005', 'Contato de desenvolvimento', true, '', 1),
  ('00000000-0000-4000-8000-000000000006', 'Contato de desenvolvimento', false, '', 1),
  ('00000000-0000-4000-8000-000000000007', 'Contato de desenvolvimento', true, '', 1),
  ('00000000-0000-4000-8000-000000000008', 'Contato de desenvolvimento', false, '', 1),
  ('00000000-0000-4000-8000-000000000009', 'Contato de desenvolvimento', false, '', 1)
ON CONFLICT ("id") DO NOTHING;

-- id = UUID do usuário ACS.
INSERT INTO "acs" ("id", "enrollmentId", "ubsId", "active")
VALUES ('00000000-0000-4000-8000-000000000002', 'ACS-001', '00000000-0000-4000-8000-000000000004', true)
ON CONFLICT ("id") DO NOTHING;

-- id = UUID do usuário admin.
INSERT INTO staff_accounts (id, "enrollmentId", active)
VALUES ('00000000-0000-4000-8000-000000000090', 'ADM-001', true)
ON CONFLICT DO NOTHING;
