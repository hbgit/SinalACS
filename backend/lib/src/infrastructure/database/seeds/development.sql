INSERT INTO ubs (id, name, address, city, state)
VALUES ('00000000-0000-4000-8000-000000000004', 'UBS Desenvolvimento', 'Endereço local', 'São Paulo', 'SP')
ON CONFLICT (id) DO NOTHING;

INSERT INTO micro_areas (id, name, ubs_id, geojson_boundary)
VALUES ('00000000-0000-4000-8000-000000000003', 'Microárea 12', '00000000-0000-4000-8000-000000000004', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (id, cpf_hash, name, birth_date, role, micro_area_id)
VALUES
  ('00000000-0000-4000-8000-000000000001', 'development-patient', 'Paciente de desenvolvimento', '1990-01-01', 'patient', '00000000-0000-4000-8000-000000000003'),
  ('00000000-0000-4000-8000-000000000002', 'development-acs', 'ACS de desenvolvimento', '1980-01-01', 'acs', '00000000-0000-4000-8000-000000000003')
ON CONFLICT (id) DO NOTHING;

INSERT INTO patients (user_id, emergency_contact)
VALUES ('00000000-0000-4000-8000-000000000001', 'Contato de desenvolvimento')
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO acs (user_id, enrollment_id, ubs_id)
VALUES ('00000000-0000-4000-8000-000000000002', 'ACS-001', '00000000-0000-4000-8000-000000000004')
ON CONFLICT (user_id) DO NOTHING;