-- examples/seed_profile.example.sql
-- Fill YOUR CV text and skills. The assistant only claims skills that exist here (source 'cv' or 'user_confirmed').
DO $seed$
DECLARE uid uuid;
BEGIN
  SELECT id INTO uid FROM users WHERE role = 'owner' AND is_active = true LIMIT 1;
  IF uid IS NULL THEN RAISE NOTICE 'No owner user found (run seed_owner first)'; RETURN; END IF;

  INSERT INTO profiles (user_id, cv_raw_text, cv_uploaded_at, min_budget_usd, freelance_preferences)
  VALUES (uid, $cv$PASTE YOUR CV TEXT HERE$cv$, now(), 5, '{"budget_hard_filter":false,"accept_small_jobs":true}'::jsonb)
  ON CONFLICT (user_id) DO UPDATE SET cv_raw_text = EXCLUDED.cv_raw_text, cv_uploaded_at = now();

  INSERT INTO skills (user_id, name, category, source, evidence)
  SELECT uid, v.name, v.category, 'cv', v.evidence
  FROM (VALUES
    ('C#',   'language',  'Listed in CV'),
    ('SQL',  'language',  'Listed in CV'),
    ('Docker','tool',     'Used in project X')
  ) AS v(name, category, evidence)
  ON CONFLICT (user_id, lower(name)) DO NOTHING;
END $seed$;
