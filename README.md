# The Gratitude Wall

A community gratitude challenge: people write one thing they're grateful for each day, see everyone's notes on a shared wall, and on December 31st receive a personal AI-written letter summarising their season of gratitude.

- **Website:** single-file `site/index.html` (no build step), hosted on Vercel
- **Database:** Supabase (Postgres) with row-level security; the site only calls three safe functions
- **Letters:** Supabase Edge Function using Groq (free plan) to write letters and Brevo to email them, scheduled with `pg_cron`

See [SETUP.md](SETUP.md) for step-by-step setup.

## Structure

```
site/index.html                           Write page + shared wall
supabase/schema.sql                       Tables, security, website functions
supabase/functions/send-letters/index.ts  Writes + emails the Dec 31 letters
supabase/schedule.sql                     Schedules the letter job
```

## Secrets

No secret keys live in this repo. The Supabase publishable key in `site/index.html` is designed to be public. The Groq key, Brevo key and admin secret are stored only as Supabase Edge Function secrets. `supabase/schedule.sql` is kept with placeholders; if you fill it in, save the filled copy as `schedule.local.sql` (git-ignored) instead.
