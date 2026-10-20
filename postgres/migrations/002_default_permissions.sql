-- 002_default_permissions.sql | per-user default permission set (spec section 23)
CREATE OR REPLACE FUNCTION seed_user_defaults(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a text;
BEGIN
  INSERT INTO profiles (user_id) VALUES (p_user) ON CONFLICT DO NOTHING;

  FOREACH a IN ARRAY ARRAY['analyze_opportunity','schedule_task','recalculate_schedule',
      'analyze_github','read_permitted_data','summarize','notify_user','manage_tasks']
  LOOP
    INSERT INTO permissions (user_id, action, mode) VALUES (p_user, a, 'auto')
    ON CONFLICT (user_id, action) DO NOTHING;
  END LOOP;

  FOREACH a IN ARRAY ARRAY['submit_form','send_message','submit_proposal',
      'github_write','github_merge','account_change','permission_change']
  LOOP
    INSERT INTO permissions (user_id, action, mode) VALUES (p_user, a, 'approval')
    ON CONFLICT (user_id, action) DO NOTHING;
  END LOOP;
END $$;
