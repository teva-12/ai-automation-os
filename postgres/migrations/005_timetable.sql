-- 005_timetable.sql
-- 1) templates may cross midnight (end_time <= start_time means "next day")
-- 2) schedule_entries.template_id marks entries generated from the timetable
-- (your own timetable is loaded separately: see examples/timetable.example.sql)
ALTER TABLE schedule_entries ADD COLUMN IF NOT EXISTS template_id uuid;

DO $fix$
DECLARE c record;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'weekly_template'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) ILIKE '%end_time > start_time%'
  LOOP
    EXECUTE format('ALTER TABLE weekly_template DROP CONSTRAINT %I', c.conname);
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'weekly_template'::regclass AND conname = 'weekly_template_times_ck') THEN
    ALTER TABLE weekly_template ADD CONSTRAINT weekly_template_times_ck CHECK (end_time <> start_time);
  END IF;
END $fix$;

CREATE OR REPLACE FUNCTION generate_schedule(p_user uuid, p_days int DEFAULT 7) RETURNS int AS $$
DECLARE n int;
BEGIN
  INSERT INTO schedule_entries (user_id, entry_date, title, session_type, start_at, end_at, planned_minutes, is_fixed, objective, template_id)
  SELECT p_user, d::date, t.title, t.session_type,
         w.s AT TIME ZONE 'Africa/Cairo', w.e AT TIME ZONE 'Africa/Cairo',
         (extract(epoch FROM (w.e - w.s)) / 60)::int, t.is_fixed, t.objective, t.id
  FROM generate_series((now() AT TIME ZONE 'Africa/Cairo')::date, (now() AT TIME ZONE 'Africa/Cairo')::date + (p_days - 1), interval '1 day') AS d
  JOIN weekly_template t ON t.user_id = p_user AND t.active AND t.weekday = extract(isodow FROM d)::int
  CROSS JOIN LATERAL (SELECT (d::date + t.start_time) AS s,
                             (d::date + t.end_time + CASE WHEN t.end_time <= t.start_time THEN interval '1 day' ELSE interval '0' END) AS e) w
  WHERE NOT EXISTS (SELECT 1 FROM schedule_entries se WHERE se.user_id = p_user AND se.start_at = (w.s AT TIME ZONE 'Africa/Cairo') AND lower(se.title) = lower(t.title));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$ LANGUAGE plpgsql;

