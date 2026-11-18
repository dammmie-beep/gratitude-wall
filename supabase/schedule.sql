-- =====================================================================
-- Schedules the letters for December 31st.
-- Run this AFTER the send-letters function is deployed and tested.
-- Replace the two YOUR_... values first (in each of the two jobs).
-- =====================================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Groq's free plan writes roughly 80 letters a day (its daily token cap),
-- and each run handles 2 letters (BATCH_SIZE). So:
--   Job 1: every 2 minutes on Dec 31 from 18:00 Lagos time to midnight.
--   Job 2: keeps going Jan 1–3 for anyone left over once Groq's daily cap resets.
--          When everyone has their letter, each run just says "done" and costs nothing.
-- Cron times are in UTC. Lagos is UTC+1.
select cron.schedule(
  'gw-send-letters',
  '*/2 17-23 31 12 *',
  $$
  select net.http_post(
    url     := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-letters',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-admin-secret', 'YOUR_ADMIN_SECRET'
    ),
    body    := '{"mode":"send"}'::jsonb,
    timeout_milliseconds := 150000
  );
  $$
);

select cron.schedule(
  'gw-send-letters-overflow',
  '*/2 * 1-3 1 *',
  $$
  select net.http_post(
    url     := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-letters',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-admin-secret', 'YOUR_ADMIN_SECRET'
    ),
    body    := '{"mode":"send"}'::jsonb,
    timeout_milliseconds := 150000
  );
  $$
);

-- Useful afterwards:
-- See it's scheduled:        select * from cron.job;
-- See recent runs:           select * from cron.job_run_details order by start_time desc limit 20;
-- Who got a letter:          select letter_status, count(*) from gw_participants group by 1;
-- Read a letter:             select * from gw_letters where email = 'someone@example.com';
-- Remove the schedules:      select cron.unschedule('gw-send-letters'); select cron.unschedule('gw-send-letters-overflow');
