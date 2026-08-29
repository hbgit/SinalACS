CREATE TABLE users (
  id UUID PRIMARY KEY,
  cpf_hash TEXT NOT NULL,
  name TEXT NOT NULL,
  birth_date DATE NOT NULL,
  role TEXT NOT NULL,
  micro_area_id UUID NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE patients (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  emergency_contact TEXT NOT NULL,
  is_chronic BOOLEAN NOT NULL DEFAULT FALSE,
  chronic_conditions JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_location_hash TEXT NULL,
  last_triage_at TIMESTAMPTZ NULL
);

CREATE TABLE acs (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  enrollment_id TEXT NOT NULL,
  ubs_id UUID NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  last_sync_at TIMESTAMPTZ NULL
);

CREATE TABLE micro_areas (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  ubs_id UUID NOT NULL,
  geojson_boundary JSONB NOT NULL
);

CREATE TABLE ubs (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL
);
