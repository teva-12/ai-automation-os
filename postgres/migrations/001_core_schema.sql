-- 001_core_schema.sql  |  AI Automation OS core schema
-- Multi-user from day one: every user-owned row carries user_id.
-- NOTE: the spec's "references" table is named learning_references because
-- REFERENCES is a reserved SQL word.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

-- ============================================================ identity
CREATE TABLE users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_id  bigint NOT NULL UNIQUE,
  display_name text   NOT NULL,
  role         text   NOT NULL DEFAULT 'member' CHECK (role IN ('owner','admin','member')),
  is_active    boolean NOT NULL DEFAULT true,
  timezone     text   NOT NULL DEFAULT 'Africa/Cairo',
  language     text   NOT NULL DEFAULT 'ar',
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
  user_id              uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  cv_file_ref          text,
  cv_raw_text          text,
  cv_parsed            jsonb,
  cv_uploaded_at       timestamptz,
  education            jsonb NOT NULL DEFAULT '[]',
  certifications       jsonb NOT NULL DEFAULT '[]',   -- only CV- or user-confirmed entries
  freelance_preferences jsonb NOT NULL DEFAULT '{}',
  min_budget_usd       numeric(10,2),                 -- NULL = no minimum (budget is never a hard filter)
  match_threshold      smallint NOT NULL DEFAULT 50 CHECK (match_threshold BETWEEN 0 AND 100),
  availability         jsonb NOT NULL DEFAULT '{}',
  learning_goals       jsonb NOT NULL DEFAULT '[]',
  notification_prefs   jsonb NOT NULL DEFAULT '{}',
  min_sleep_hours      numeric(3,1) NOT NULL DEFAULT 8.0,
  schedule_config      jsonb NOT NULL DEFAULT '{}',
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE skills (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  category    text NOT NULL DEFAULT 'other'
              CHECK (category IN ('language','framework','tool','concept','soft','other')),
  proficiency text,
  -- anti-fabrication guard: a skill must come from the CV or be confirmed by the user
  source      text NOT NULL CHECK (source IN ('cv','user_confirmed')),
  evidence    text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX skills_user_name_uq ON skills (user_id, lower(name));

-- portfolio / personal / college projects (NOT paid freelance work)
CREATE TABLE projects (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  tech_stack  text[] NOT NULL DEFAULT '{}',
  repo_url    text,
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','completed','archived')),
  source      text NOT NULL DEFAULT 'user_confirmed' CHECK (source IN ('cv','user_confirmed')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX projects_user_idx ON projects(user_id);

-- ============================================================ freelance
CREATE TABLE freelance_opportunities (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform         text NOT NULL,
  external_id      text NOT NULL,
  url              text,
  title            text NOT NULL,
  description      text,
  budget_min       numeric(12,2),
  budget_max       numeric(12,2),
  currency         text,
  deadline         timestamptz,
  posted_at        timestamptz,
  ingestion_source text NOT NULL DEFAULT 'manual'
                   CHECK (ingestion_source IN ('api','rss','email','forwarded','manual')),
  submitted_by     uuid REFERENCES users(id) ON DELETE SET NULL,
  content_hash     text,
  raw              jsonb,
  normalized       jsonb,
  complexity       text CHECK (complexity IN ('simple','complex')),
  status           text NOT NULL DEFAULT 'DISCOVERED' CHECK (status IN ('DISCOVERED','ANALYZED','EXPIRED')),
  discovered_at    timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (platform, external_id)
);
CREATE INDEX opp_hash_idx ON freelance_opportunities(content_hash);
CREATE INDEX opp_status_idx ON freelance_opportunities(status, discovered_at DESC);

-- per-user scoring of a shared opportunity (enables team ranking later)
CREATE TABLE opportunity_matches (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id        uuid NOT NULL REFERENCES freelance_opportunities(id) ON DELETE CASCADE,
  user_id               uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  match_score           numeric(5,2) NOT NULL CHECK (match_score BETWEEN 0 AND 100),
  strong_matches        jsonb NOT NULL DEFAULT '[]',
  missing_skills        jsonb NOT NULL DEFAULT '[]',
  risks                 jsonb NOT NULL DEFAULT '[]',
  estimated_effort_hours numeric(6,1),
  estimated_time        text,
  recommendation        text,
  analysis              jsonb,
  notified_at           timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (opportunity_id, user_id)
);
CREATE INDEX opp_match_user_idx ON opportunity_matches(user_id, match_score DESC);

CREATE TABLE applications (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  opportunity_id uuid NOT NULL REFERENCES freelance_opportunities(id) ON DELETE CASCADE,
  state          text NOT NULL DEFAULT 'NOTIFIED' CHECK (state IN
                 ('DISCOVERED','ANALYZED','NOTIFIED','OPENED','PROPOSAL_DRAFTED',
                  'PROPOSAL_SUBMITTED','REJECTED','ACCEPTED','IGNORED','EXPIRED')),
  proposal_draft text,
  submitted_at   timestamptz,
  notes          text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, opportunity_id)
);

CREATE TABLE freelance_projects (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  opportunity_id uuid REFERENCES freelance_opportunities(id) ON DELETE SET NULL,
  application_id uuid REFERENCES applications(id) ON DELETE SET NULL,
  client_name    text,
  title          text NOT NULL,
  requirements   text,
  deliverables   jsonb NOT NULL DEFAULT '[]',
  budget         numeric(12,2),
  currency       text,
  deadline       timestamptz,
  priority       text NOT NULL DEFAULT 'high' CHECK (priority IN ('low','medium','high','urgent')),
  estimated_hours numeric(6,1),
  status         text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','delivered','cancelled')),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX fproj_user_idx ON freelance_projects(user_id, status);

-- ============================================================ tasks
CREATE TABLE task_sources (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type  text NOT NULL CHECK (source_type IN
               ('telegram_message','forwarded_message','whatsapp_forward','manual','github','ai_generated')),
  external_ref text,
  raw_content  text,
  metadata     jsonb NOT NULL DEFAULT '{}',
  dedupe_key   text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX task_sources_dedupe_uq ON task_sources(user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;

CREATE TABLE tasks (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title             text NOT NULL,
  description       text,
  category          text,                       -- e.g. '.NET','DB','German','College','Freelance'
  subject           text,                       -- e.g. 'Big Data'
  priority          text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
  status            text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','in_progress','done','deferred','cancelled')),
  deadline          timestamptz,
  estimated_minutes integer CHECK (estimated_minutes > 0),
  energy_required   text CHECK (energy_required IN ('low','medium','high')),
  project_id        uuid REFERENCES projects(id) ON DELETE SET NULL,
  freelance_project_id uuid REFERENCES freelance_projects(id) ON DELETE SET NULL,
  source_id         uuid REFERENCES task_sources(id) ON DELETE SET NULL,
  carried_over_count integer NOT NULL DEFAULT 0,
  completed_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tasks_user_status_idx ON tasks(user_id, status, deadline);

CREATE TABLE task_dependencies (
  task_id            uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  depends_on_task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, depends_on_task_id),
  CHECK (task_id <> depends_on_task_id)
);

-- ============================================================ schedule
-- sessions = recurring weekly templates (configurable, never invented by the AI)
CREATE TABLE sessions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name             text NOT NULL,
  session_type     text NOT NULL,               -- sleep, college, dotnet, db, german, initiative, ...
  subject          text,
  day_of_week      smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),  -- ISO: 1=Mon .. 7=Sun
  start_time       time NOT NULL,
  end_time         time NOT NULL,
  default_minutes  integer NOT NULL DEFAULT 180 CHECK (default_minutes > 0),
  is_fixed         boolean NOT NULL DEFAULT false,
  is_active        boolean NOT NULL DEFAULT true,
  notes            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_day_idx ON sessions(user_id, day_of_week);

-- schedule_entries = concrete per-date instances produced by the scheduler
CREATE TABLE schedule_entries (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id       uuid REFERENCES sessions(id) ON DELETE SET NULL,
  entry_date       date NOT NULL,
  title            text NOT NULL,
  session_type     text NOT NULL,
  start_at         timestamptz NOT NULL,
  end_at           timestamptz NOT NULL,
  planned_minutes  integer NOT NULL,
  actual_minutes   integer,
  status           text NOT NULL DEFAULT 'planned'
                   CHECK (status IN ('planned','in_progress','completed','skipped','moved','shortened')),
  is_fixed         boolean NOT NULL DEFAULT false,
  objective        text,
  moved_from_entry_id uuid REFERENCES schedule_entries(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (end_at > start_at)
);
CREATE INDEX sched_user_date_idx ON schedule_entries(user_id, entry_date, start_at);

CREATE TABLE schedule_entry_tasks (
  schedule_entry_id uuid NOT NULL REFERENCES schedule_entries(id) ON DELETE CASCADE,
  task_id           uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  PRIMARY KEY (schedule_entry_id, task_id)
);

CREATE TABLE goals (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       text NOT NULL,
  description text,
  target_date date,
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active','achieved','dropped')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE deadlines (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      text NOT NULL,
  due_at     timestamptz NOT NULL,
  kind       text NOT NULL DEFAULT 'general' CHECK (kind IN ('college','freelance','project','learning','general')),
  is_hard    boolean NOT NULL DEFAULT true,
  task_id    uuid REFERENCES tasks(id) ON DELETE CASCADE,
  freelance_project_id uuid REFERENCES freelance_projects(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX deadlines_user_due_idx ON deadlines(user_id, due_at);

-- ============================================================ learning
CREATE TABLE learning_paths (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  subject     text,
  description text,
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','completed')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- user-provided (or official docs) only; the AI never invents references
CREATE TABLE learning_references (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  learning_path_id uuid REFERENCES learning_paths(id) ON DELETE SET NULL,
  subject          text NOT NULL,
  kind             text NOT NULL CHECK (kind IN ('book','playlist','docs','course','other')),
  skill_focus      text CHECK (skill_focus IN ('reading','listening','speaking','writing','general')),
  title            text NOT NULL,
  url              text,
  source           text NOT NULL CHECK (source IN ('user_provided','official_docs')),
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lref_user_subject_idx ON learning_references(user_id, subject);

CREATE TABLE learning_path_steps (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  learning_path_id uuid NOT NULL REFERENCES learning_paths(id) ON DELETE CASCADE,
  position         integer NOT NULL,
  title            text NOT NULL,
  reference_id     uuid REFERENCES learning_references(id) ON DELETE SET NULL,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_progress','done')),
  UNIQUE (learning_path_id, position)
);

-- ============================================================ github
CREATE TABLE github_repositories (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  owner          text NOT NULL,
  name           text NOT NULL,
  alias          text,
  default_branch text,
  is_watched     boolean NOT NULL DEFAULT true,
  last_polled_at timestamptz,
  last_seen_sha  text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, owner, name)
);

CREATE TABLE github_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  repo_id      uuid NOT NULL REFERENCES github_repositories(id) ON DELETE CASCADE,
  event_type   text NOT NULL CHECK (event_type IN ('push','commit','pull_request','merge','branch','other')),
  dedupe_key   text NOT NULL,                  -- e.g. sha or PR number+action
  branch       text,
  sha          text,
  actor        text,
  title        text,
  payload      jsonb,
  analysis     jsonb,
  analyzed_at  timestamptz,
  occurred_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (repo_id, dedupe_key)
);
CREATE INDEX gh_events_repo_idx ON github_events(repo_id, occurred_at DESC);

-- ============================================================ comms & control
CREATE TABLE notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        text NOT NULL,                   -- opportunity, session, github, deadline, system ...
  importance  text NOT NULL DEFAULT 'normal' CHECK (importance IN ('low','normal','high','critical')),
  title       text,
  body        text,
  payload     jsonb NOT NULL DEFAULT '{}',
  dedupe_key  text,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed','suppressed')),
  sent_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX notif_dedupe_uq ON notifications(user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX notif_user_idx ON notifications(user_id, created_at DESC);

CREATE TABLE conversations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chat_id        bigint NOT NULL,
  role           text NOT NULL CHECK (role IN ('user','assistant','tool','system')),
  content        text NOT NULL,
  intent         text,
  correlation_id uuid,
  metadata       jsonb NOT NULL DEFAULT '{}',
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX conv_user_time_idx ON conversations(user_id, created_at DESC);

CREATE TABLE automation_rules (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       text NOT NULL,
  trigger    jsonb NOT NULL,
  action     jsonb NOT NULL,
  enabled    boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- permission model: AUTO / APPROVAL / DENY per action
CREATE TABLE permissions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action     text NOT NULL,
  mode       text NOT NULL CHECK (mode IN ('auto','approval','deny')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, action)
);

-- pending approvals for WF-19 (inline Confirm / Cancel buttons)
CREATE TABLE approvals (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action         text NOT NULL,
  target         text,
  payload        jsonb NOT NULL DEFAULT '{}',
  status         text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','expired','executed')),
  correlation_id uuid,
  requested_at   timestamptz NOT NULL DEFAULT now(),
  decided_at     timestamptz,
  expires_at     timestamptz NOT NULL DEFAULT now() + interval '24 hours'
);
CREATE INDEX approvals_pending_idx ON approvals(user_id, status);

-- append-only audit trail
CREATE TABLE audit_logs (
  id             bigserial PRIMARY KEY,
  user_id        uuid REFERENCES users(id) ON DELETE SET NULL,
  correlation_id uuid,
  workflow       text,
  actor          text NOT NULL DEFAULT 'system' CHECK (actor IN ('user','ai','system')),
  action         text NOT NULL,
  target         text,
  status         text NOT NULL CHECK (status IN ('success','failure','pending','denied')),
  result         jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_user_time_idx ON audit_logs(user_id, created_at DESC);
CREATE INDEX audit_corr_idx ON audit_logs(correlation_id);

CREATE OR REPLACE FUNCTION audit_logs_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'audit_logs is append-only'; END $$;
CREATE TRIGGER audit_logs_no_change BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable();

-- ============================================================ updated_at triggers
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['users','profiles','skills','projects','freelance_opportunities',
    'applications','freelance_projects','tasks','sessions','schedule_entries','goals',
    'learning_paths','automation_rules','permissions']
  LOOP
    EXECUTE format('CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
                    FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t);
  END LOOP;
END $$;
