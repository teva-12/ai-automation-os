-- 003_freelance_pipeline.sql
-- Short job codes (J1, J2, ...) used by the assistant ("proposal J12").
-- Safe to re-run: every statement is idempotent.
CREATE SEQUENCE IF NOT EXISTS opp_code_seq;
ALTER TABLE freelance_opportunities ADD COLUMN IF NOT EXISTS short_code text;
ALTER TABLE freelance_opportunities ALTER COLUMN short_code SET DEFAULT ('J' || nextval('opp_code_seq')::text);
UPDATE freelance_opportunities SET short_code = 'J' || nextval('opp_code_seq')::text WHERE short_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS opp_short_code_uq ON freelance_opportunities (short_code);
