CREATE TABLE visits (
  id UUID PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(user_id),
  acs_id UUID NOT NULL REFERENCES acs(user_id),
  scheduled_at TIMESTAMPTZ NOT NULL,
  started_at TIMESTAMPTZ NULL,
  completed_at TIMESTAMPTZ NULL,
  status TEXT NOT NULL,
  risk_level_before TEXT NOT NULL,
  risk_level_after TEXT NULL,
  notes JSONB NOT NULL DEFAULT '{}'::jsonb,
  sync_status TEXT NOT NULL DEFAULT 'PENDING',
  local_id UUID NOT NULL,
  sync_at TIMESTAMPTZ NULL,
  version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE alerts (
  id UUID PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(user_id),
  acs_id UUID NULL REFERENCES acs(user_id),
  triggered_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NULL,
  responded_at TIMESTAMPTZ NULL,
  risk_level TEXT NOT NULL,
  location_hash TEXT NOT NULL,
  status TEXT NOT NULL,
  mqtt_topic TEXT NOT NULL,
  device_id TEXT NOT NULL,
  retry_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE triage_sessions (
  id UUID PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(user_id),
  answers JSONB NOT NULL,
  result_risk TEXT NOT NULL,
  result_display TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  device_id TEXT NOT NULL
);

CREATE TABLE consent_logs (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  purpose TEXT NOT NULL,
  action TEXT NOT NULL,
  version TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_hash TEXT NOT NULL,
  user_agent TEXT NOT NULL,
  signature TEXT NOT NULL
);

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  action_type TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_hash TEXT NOT NULL,
  result TEXT NOT NULL
);
