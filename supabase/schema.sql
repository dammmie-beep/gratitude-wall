-- =====================================================================
-- The Gratitude Wall: database setup
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to run in a project that already has your March "entries" table:
-- everything here is prefixed gw_ so nothing old is touched.
-- =====================================================================

-- ---------- Tables ----------
create table if not exists public.gw_participants (
  email             text primary key,
  name              text not null,
  created_at        timestamptz not null default now(),
  letter_status     text not null default 'pending'
                    check (letter_status in ('pending','processing','sent','failed','skipped')),
  letter_claimed_at timestamptz,
  letter_sent_at    timestamptz,
  letter_error      text
);

create table if not exists public.gw_entries (
  id          bigint generated always as identity primary key,
  email       text not null references public.gw_participants(email) on delete cascade,
  name        text not null,
  text        text not null check (char_length(text) between 3 and 600),
  category    text check (category in ('people','moments','health','growth','work','faith','simple')),
  visibility  text not null default 'public' check (visibility in ('public','anonymous','private')),
  entry_date  date not null default (now() at time zone 'Africa/Lagos')::date,
  created_at  timestamptz not null default now()
);
create index if not exists gw_entries_email_idx on public.gw_entries (email, entry_date);
create index if not exists gw_entries_wall_idx  on public.gw_entries (id desc) where visibility <> 'private';

-- Each person's finished letter is kept here too, so nothing is lost if an email bounces.
create table if not exists public.gw_letters (
  email       text primary key references public.gw_participants(email) on delete cascade,
  subject     text not null,
  letter      text not null,
  created_at  timestamptz not null default now()
);

-- ---------- Lock the tables ----------
-- Row level security ON with no policies = the public website can't read or
-- change the tables directly. It can only use the three functions below,
-- which never reveal emails or private entries.
alter table public.gw_participants enable row level security;
alter table public.gw_entries      enable row level security;
alter table public.gw_letters      enable row level security;

-- ---------- Website functions ----------

-- Save an entry. Returns how many different days this person has written on.
create or replace function public.gw_submit(
  p_email text, p_name text, p_text text, p_category text, p_visibility text
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(p_email));
  v_name  text := left(trim(p_name), 60);
  v_text  text := trim(p_text);
  v_today date := (now() at time zone 'Africa/Lagos')::date;
  v_days  integer;
begin
  if v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then raise exception 'invalid email'; end if;
  if char_length(v_name) < 2 then raise exception 'invalid name'; end if;
  if char_length(v_text) < 3 or char_length(v_text) > 600 then raise exception 'invalid text'; end if;
  if p_visibility not in ('public','anonymous','private') then p_visibility := 'public'; end if;
  if p_category is not null and p_category not in ('people','moments','health','growth','work','faith','simple') then
    p_category := null;
  end if;

  -- simple spam guard: at most 5 entries per email per day
  if (select count(*) from gw_entries where email = v_email and entry_date = v_today) >= 5 then
    raise exception 'daily limit reached';
  end if;

  insert into gw_participants (email, name) values (v_email, v_name)
  on conflict (email) do update set name = excluded.name;

  insert into gw_entries (email, name, text, category, visibility, entry_date)
  values (v_email, v_name, v_text, p_category, p_visibility, v_today);

  select count(distinct entry_date) into v_days from gw_entries where email = v_email;
  return v_days;
end $$;

-- The public wall: newest first, no emails, no private entries, first names only.
create or replace function public.gw_wall(p_limit integer default 60, p_before bigint default null)
returns table (id bigint, display_name text, text text, category text, entry_date date)
language sql security definer set search_path = public stable as $$
  select e.id,
         case when e.visibility = 'anonymous' then 'Anonymous' else split_part(e.name, ' ', 1) end,
         e.text, e.category, e.entry_date
  from gw_entries e
  where e.visibility <> 'private'
    and (p_before is null or e.id < p_before)
  order by e.id desc
  limit least(greatest(p_limit, 1), 200);
$$;

-- Totals for the wall header (counts private entries too, but reveals nothing about them).
create or replace function public.gw_stats()
returns table (people bigint, entries bigint)
language sql security definer set search_path = public stable as $$
  select (select count(*) from gw_participants), (select count(*) from gw_entries);
$$;

grant execute on function public.gw_submit(text,text,text,text,text) to anon, authenticated;
grant execute on function public.gw_wall(integer,bigint)            to anon, authenticated;
grant execute on function public.gw_stats()                          to anon, authenticated;

-- ---------- Letter-job function (server only, never the website) ----------
-- Hands the letter job a small batch of people who still need a letter,
-- marking them "processing" so two runs never write to the same person twice.
create or replace function public.gw_claim_batch(p_size integer)
returns setof public.gw_participants
language sql security definer set search_path = public as $$
  update gw_participants p
     set letter_status = 'processing', letter_claimed_at = now()
   where p.email in (
     select email from gw_participants
      where letter_status = 'pending'
         or (letter_status = 'processing' and letter_claimed_at < now() - interval '10 minutes')
      order by created_at
      limit p_size
      for update skip locked)
  returning p.*;
$$;
revoke execute on function public.gw_claim_batch(integer) from public, anon, authenticated;
grant  execute on function public.gw_claim_batch(integer) to service_role;
