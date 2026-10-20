-- examples/timetable.example.sql
-- Load YOUR weekly timetable. weekday: ISO (Mon=1 ... Sun=7). If end_time <= start_time the slot ends the next day.
-- session_type is free text; 'sleep', 'rest' and 'break' are silent (no Telegram messages).
-- Re-running replaces the template and the FUTURE planned generated entries only.
DO $seed$
DECLARE uid uuid;
BEGIN
  SELECT id INTO uid FROM users WHERE role = 'owner' AND is_active = true LIMIT 1;
  IF uid IS NULL THEN RAISE NOTICE 'No owner user found'; RETURN; END IF;
  DELETE FROM schedule_entries WHERE user_id = uid AND template_id IS NOT NULL AND status = 'planned' AND start_at > now();
  DELETE FROM weekly_template WHERE user_id = uid;
  INSERT INTO weekly_template (user_id, weekday, start_time, end_time, title, session_type, is_fixed) VALUES
    (uid, 6, '00:00'::time, '08:00'::time, 'Sleep',        'sleep',   true),
    (uid, 6, '09:00'::time, '15:00'::time, 'University',   'college', true),
    (uid, 6, '17:00'::time, '20:00'::time, 'Backend study','dotnet',  false),
    (uid, 6, '21:00'::time, '23:00'::time, 'Networking',   'subject', false),
    (uid, 7, '10:00'::time, '13:00'::time, 'Project work', 'tasks',   false),
    (uid, 7, '16:00'::time, '19:00'::time, 'Backend study','dotnet',  false),
    (uid, 7, '22:00'::time, '02:00'::time, 'Security lab', 'security',false);
  PERFORM generate_schedule(uid, 7);
END $seed$;
