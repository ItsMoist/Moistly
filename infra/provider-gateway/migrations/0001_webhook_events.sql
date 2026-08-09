PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS webhook_events (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  capability TEXT NOT NULL,
  webhook_id TEXT,
  provider_event_id TEXT,
  monitor TEXT,
  monitored_address TEXT,
  event_type TEXT,
  chain TEXT,
  tx_hash TEXT,
  block_number INTEGER,
  from_address TEXT,
  to_address TEXT,
  contract_address TEXT,
  method_selector TEXT,
  signature_valid INTEGER NOT NULL DEFAULT 0,
  raw_payload TEXT NOT NULL,
  received_at TEXT NOT NULL,
  queued_at TEXT,
  processed_at TEXT,
  processing_status TEXT NOT NULL DEFAULT 'received',
  processing_attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  UNIQUE(provider, provider_event_id)
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_provider_received
  ON webhook_events(provider, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_events_monitor
  ON webhook_events(monitor, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_events_monitored_address
  ON webhook_events(monitored_address, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_events_from
  ON webhook_events(from_address, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_events_to
  ON webhook_events(to_address, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_events_contract
  ON webhook_events(contract_address, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_events_tx
  ON webhook_events(tx_hash);
CREATE INDEX IF NOT EXISTS idx_webhook_events_status
  ON webhook_events(processing_status, received_at);

CREATE TABLE IF NOT EXISTS processor_deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL,
  destination TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  status_code INTEGER,
  delivered_at TEXT,
  error TEXT,
  FOREIGN KEY(event_id) REFERENCES webhook_events(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_processor_deliveries_event
  ON processor_deliveries(event_id, attempt);
