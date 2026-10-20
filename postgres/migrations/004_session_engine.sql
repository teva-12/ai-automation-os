-- 004_session_engine.sql
-- Weekly timetable template + generator that fills schedule_entries for the next N days.
-- weekday uses ISO numbering: 1=Monday ... 7=Sunday.
CREATE TABLE IF NOT EXISTS weekly_template (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
  start_time time NOT NULL,
  end_time time NOT NULL,
  title text NOT NULL,
  session_type text NOT NULL DEFAULT 'general',
  is_fixed boolean NOT NULL DEFAULT false,
  objective text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_time > start_time),
  UNIQUE (user_id, weekday, start_time, title)
);

CREATE OR REPLACE FUNCTION generate_schedule(p_user uuid, p_days int DEFAULT 7) RETURNS int AS $$
DECLARE n int;
BEGIN
  INSERT INTO schedule_entries (user_id, entry_date, title, session_type, start_at, end_at, planned_minutes, is_fixed, objective)
  SELECT p_user, d::date, t.title, t.session_type,
         (d::date + t.start_time) AT TIME ZONE 'Africa/Cairo',
         (d::date + t.end_time)   AT TIME ZONE 'Africa/Cairo',
         (extract(epoch FROM (t.end_time - t.start_time)) / 60)::int,
         t.is_fixed, t.objective
  FROM generate_series((now() AT TIME ZONE 'Africa/Cairo')::date, (now() AT TIME ZONE 'Africa/Cairo')::date + (p_days - 1), interval '1 day') AS d
  JOIN weekly_template t ON t.user_id = p_user AND t.active AND t.weekday = extract(isodow FROM d)::int
  WHERE NOT EXISTS (
    SELECT 1 FROM schedule_entries se
    WHERE se.user_id = p_user AND se.entry_date = d::date AND lower(se.title) = lower(t.title)
      AND se.start_at = (d::date + t.start_time) AT TIME ZONE 'Africa/Cairo');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$ LANGUAGE plpgsql;
