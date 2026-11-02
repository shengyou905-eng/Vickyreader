-- Candidate 010. Apply only after approval; never run schema.sql on an existing DB.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
CREATE TABLE reading_recaps (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT,
  state TEXT NOT NULL CHECK (state IN (
    'prepared','generating','ready','stale','invalidated','deleted',
    'failed','cancelled','expired')),
  is_saved BOOLEAN NOT NULL DEFAULT false,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  schema_version INTEGER NOT NULL DEFAULT 1 CHECK (schema_version > 0),
  prompt_version TEXT,
  source_fingerprint TEXT CHECK (source_fingerprint ~ '^[a-f0-9]{64}$'),
  selected_sources_json JSONB,
  coverage_json JSONB,
  result_json JSONB,
  requested_model TEXT,
  returned_model TEXT,
  input_tokens BIGINT CHECK (input_tokens >= 0),
  output_tokens BIGINT CHECK (output_tokens >= 0),
  elapsed_ms BIGINT CHECK (elapsed_ms >= 0),
  cost_amount NUMERIC(18,8) CHECK (cost_amount >= 0),
  cost_currency TEXT,
  pricing_version TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  UNIQUE (id, user_id),
  UNIQUE (id, user_id, book_id),
  CHECK (book_id IS NULL OR
    (length(book_id) BETWEEN 1 AND 200 AND btrim(book_id) = book_id)),
  CHECK (state IN ('deleted','invalidated') OR book_id IS NOT NULL),
  CHECK (state <> 'ready' OR
    (result_json IS NOT NULL AND source_fingerprint IS NOT NULL
     AND prompt_version IS NOT NULL AND coverage_json IS NOT NULL
     AND selected_sources_json IS NOT NULL)),
  CHECK (state = 'ready' OR result_json IS NULL),
  CHECK (coverage_json IS NULL OR jsonb_typeof(coverage_json) = 'object'),
  CHECK (selected_sources_json IS NULL OR
    (jsonb_typeof(selected_sources_json) = 'array'
     AND octet_length(selected_sources_json::text) <= 65536)),
  CHECK (result_json IS NULL OR
    (jsonb_typeof(result_json) = 'object' AND octet_length(result_json::text) <= 131072)),
  CHECK ((state = 'deleted') = (deleted_at IS NOT NULL)),
  CHECK (NOT is_saved OR state IN ('ready','stale','invalidated')),
  CHECK (state NOT IN ('deleted','invalidated') OR
    (book_id IS NULL AND source_fingerprint IS NULL AND coverage_json IS NULL
     AND selected_sources_json IS NULL
     AND prompt_version IS NULL AND requested_model IS NULL AND returned_model IS NULL
     AND input_tokens IS NULL AND output_tokens IS NULL AND elapsed_ms IS NULL
     AND cost_amount IS NULL AND cost_currency IS NULL AND pricing_version IS NULL))
);
CREATE INDEX idx_reading_recaps_owner_list
  ON reading_recaps (user_id, updated_at DESC, id DESC) WHERE is_saved;
CREATE INDEX idx_reading_recaps_owner_book
  ON reading_recaps (user_id, book_id, state);
CREATE INDEX idx_reading_recaps_expiry
  ON reading_recaps (expires_at) WHERE NOT is_saved AND expires_at IS NOT NULL;

CREATE TABLE reading_recap_sources (
  recap_id UUID NOT NULL,
  user_id UUID NOT NULL,
  book_id TEXT NOT NULL,
  evidence_id TEXT NOT NULL CHECK (length(evidence_id) BETWEEN 1 AND 256),
  entry_id UUID NOT NULL,
  follow_up_id UUID,
  client_entry_id TEXT,
  source_field TEXT NOT NULL CHECK (length(source_field) BETWEEN 1 AND 128),
  source_kind TEXT NOT NULL CHECK (source_kind IN (
    'book_excerpt','highlight','user_note','user_question','historical_ai','ai_prompt')),
  provenance TEXT NOT NULL,
  source_digest TEXT NOT NULL CHECK (source_digest ~ '^[a-f0-9]{64}$'),
  follow_up_set_digest TEXT NOT NULL CHECK (follow_up_set_digest ~ '^[a-f0-9]{64}$'),
  observed_revision BIGINT CHECK (observed_revision >= 0),
  observed_writer_id UUID,
  locator_json JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(locator_json) = 'object' AND octet_length(locator_json::text) <= 2048),
  PRIMARY KEY (recap_id, evidence_id),
  FOREIGN KEY (recap_id, user_id, book_id)
    REFERENCES reading_recaps(id, user_id, book_id) ON DELETE CASCADE
);
CREATE INDEX idx_recap_sources_entry ON reading_recap_sources(user_id, entry_id);
CREATE INDEX idx_recap_sources_follow ON reading_recap_sources(user_id, follow_up_id)
  WHERE follow_up_id IS NOT NULL;

CREATE TABLE reading_recap_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recap_id UUID NOT NULL,
  user_id UUID NOT NULL,
  client_request_id UUID NOT NULL,
  item_id TEXT CHECK (length(item_id) BETWEEN 1 AND 256),
  category TEXT NOT NULL CHECK (category IN ('inaccurate','low_value','wrong_relation')),
  comment TEXT NOT NULL DEFAULT '' CHECK (length(comment) <= 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, client_request_id),
  FOREIGN KEY (recap_id, user_id) REFERENCES reading_recaps(id, user_id) ON DELETE CASCADE
);
CREATE INDEX idx_recap_feedback_owner ON reading_recap_feedback(user_id, recap_id);

CREATE TABLE reading_recap_operations (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id UUID NOT NULL,
  recap_id UUID NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('prepare','generate','save','follow_up','feedback')),
  request_mac TEXT CHECK (request_mac ~ '^[a-f0-9]{64}$'),
  mac_key_version TEXT,
  expected_revision BIGINT NOT NULL CHECK (expected_revision > 0),
  generation_id UUID NOT NULL DEFAULT gen_random_uuid(),
  status TEXT NOT NULL CHECK (status IN (
    'running','succeeded','failed','cancelled','interrupted','expired','revoked')),
  result_id UUID,
  error_code TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  deadline_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, request_id),
  FOREIGN KEY (recap_id, user_id) REFERENCES reading_recaps(id, user_id) ON DELETE CASCADE,
  CHECK (status <> 'running' OR finished_at IS NULL)
);
CREATE INDEX idx_recap_ops_recap ON reading_recap_operations(user_id, recap_id);
CREATE UNIQUE INDEX idx_recap_ops_one_model_request
  ON reading_recap_operations(user_id, recap_id)
  WHERE status = 'running' AND operation IN ('generate','follow_up');

ALTER TABLE xiaou_conversations ADD COLUMN recap_id UUID;
ALTER TABLE xiaou_conversations ADD CONSTRAINT xiaou_recap_owner_fk
  FOREIGN KEY (recap_id, user_id) REFERENCES reading_recaps(id, user_id) ON DELETE CASCADE;
ALTER TABLE xiaou_conversations ADD CONSTRAINT xiaou_recap_kind_ck CHECK (
  (recap_id IS NULL AND kind <> 'book_recap') OR
  (recap_id IS NOT NULL AND kind = 'book_recap')
) NOT VALID;
CREATE UNIQUE INDEX idx_xiaou_conversation_recap
  ON xiaou_conversations(recap_id) WHERE recap_id IS NOT NULL;

ALTER TABLE xiaou_conversations VALIDATE CONSTRAINT xiaou_recap_kind_ck;
COMMIT;
