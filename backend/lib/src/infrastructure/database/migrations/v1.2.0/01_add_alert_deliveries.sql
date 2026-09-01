ALTER TABLE alerts
  ADD COLUMN IF NOT EXISTS micro_area_id UUID,
  ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS alerts_micro_area_status_idx
  ON alerts (micro_area_id, status, triggered_at DESC);

CREATE TABLE IF NOT EXISTS alert_deliveries (
  alert_id UUID NOT NULL REFERENCES alerts(id),
  acs_id UUID NOT NULL REFERENCES acs(user_id),
  acknowledged_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (alert_id, acs_id)
);