-- IMS Volleyball: database setup for Supabase.
-- Paste this whole file into Supabase > SQL Editor > New query, and press Run.
-- It is safe to run again later (it replaces the rules, it keeps your data).

-- 1. One table holds everything, keyed by a path:
--    weeks/<id>    a Sunday's fixtures (organiser only)
--    scores/<id>   a match result
--    live/<id>     a live count saved mid-match so another phone can carry on
--    config/league the league name (organiser only)
create table if not exists public.docs (
  path text primary key check (path ~ '^(weeks|scores|live|config)/[A-Za-z0-9_.-]{1,160}$'),
  data jsonb not null,
  updated_at timestamptz not null default now()
);

-- 2. Organisers. Add yourself with the line in README step 3.
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- 3. Score checks (the same rules as the website: sets to 25, 25, 15, win by 2).
create or replace function public.ims_set_error(a int, b int, t int) returns text
language plpgsql immutable as $$
declare hi int := greatest(a, b); lo int := least(a, b);
begin
  if a is null or b is null or a < 0 or b < 0 or a > 99 or b > 99 then return 'bad number'; end if;
  if a = b then return 'level'; end if;
  if hi < t then return 'winner needs ' || t; end if;
  if hi - lo < 2 then return 'must be won by 2'; end if;
  if hi > t and hi - lo <> 2 then return 'past ' || t || ' it ends at 2 ahead'; end if;
  return null;
end $$;

create or replace function public.ims_score_error(sets jsonb) returns text
language plpgsql immutable as $$
declare
  targets int[] := array[25, 25, 15];
  s jsonb; a int; b int; err text; wins_a int := 0; wins_b int := 0; i int;
begin
  if sets is null or jsonb_typeof(sets) <> 'array' or jsonb_array_length(sets) > 3 then return 'sets missing'; end if;
  for i in 0..2 loop
    s := sets -> i;
    if s is null or jsonb_typeof(s) = 'null' then
      if i < 2 then return 'set ' || (i + 1) || ' missing'; end if;
      continue;
    end if;
    if jsonb_typeof(s) <> 'array' or jsonb_array_length(s) <> 2
       or jsonb_typeof(s -> 0) <> 'number' or jsonb_typeof(s -> 1) <> 'number' then
      return 'set ' || (i + 1) || ' malformed';
    end if;
    if i = 2 and wins_a <> 1 then return 'set 3 only after 1-1'; end if;
    if (s ->> 0)::numeric % 1 <> 0 or (s ->> 1)::numeric % 1 <> 0
       or abs((s ->> 0)::numeric) > 99 or abs((s ->> 1)::numeric) > 99 then
      return 'set ' || (i + 1) || ': whole numbers only';
    end if;
    a := (s ->> 0)::numeric; b := (s ->> 1)::numeric;
    err := public.ims_set_error(a, b, targets[i + 1]);
    if err is not null then return 'set ' || (i + 1) || ': ' || err; end if;
    if a > b then wins_a := wins_a + 1; else wins_b := wins_b + 1; end if;
  end loop;
  if greatest(wins_a, wins_b) <> 2 then return 'no winner'; end if;
  return null;
end $$;

-- 4. Checks every write that isn't from the organiser.
create or replace function public.ims_live_ok(d jsonb) returns boolean
language sql immutable as $$
  select jsonb_typeof(d) = 'object'
    and jsonb_typeof(d -> 'cur') = 'array' and jsonb_array_length(d -> 'cur') = 2
    and jsonb_typeof(d -> 'cur' -> 0) = 'number' and jsonb_typeof(d -> 'cur' -> 1) = 'number'
    and jsonb_typeof(d -> 'done') = 'array' and jsonb_array_length(d -> 'done') <= 3
    and not exists (
      select 1 from jsonb_array_elements(d -> 'done') s
      where jsonb_typeof(s) <> 'array' or jsonb_array_length(s) <> 2
         or jsonb_typeof(s -> 0) <> 'number' or jsonb_typeof(s -> 1) <> 'number'
    );
$$;

create or replace function public.docs_guard() returns trigger
language plpgsql set search_path = public as $$
declare err text; match_id text; fixture jsonb;
begin
  new.updated_at := now();
  -- the organiser, and the SQL editor itself, skip the checks
  if current_user not in ('anon', 'authenticated') or public.is_admin() then return new; end if;
  if octet_length(new.data::text) > 4000 then raise exception 'too large' using errcode = '22000'; end if;
  match_id := substr(new.path, strpos(new.path, '/') + 1);
  select m into fixture from public.docs w, jsonb_array_elements(w.data -> 'matches') m
    where w.path like 'weeks/%' and m ->> 'id' = match_id limit 1;
  if fixture is null then raise exception 'unknown match' using errcode = '22000'; end if;
  if new.path like 'live/%' then
    if not public.ims_live_ok(new.data) then raise exception 'bad live count' using errcode = '22000'; end if;
  elsif new.path like 'scores/%' then
    err := public.ims_score_error(new.data -> 'sets');
    if err is not null then raise exception 'invalid score: %', err using errcode = '22000'; end if;
    if coalesce(new.data ->> 'side', '') not in ('A', 'B') then raise exception 'side must be A or B' using errcode = '22000'; end if;
    -- keep only what a captain may send; names come from the fixture
    new.data := jsonb_build_object('sets', new.data -> 'sets', 'side', new.data ->> 'side',
      'home', fixture ->> 'home', 'away', fixture ->> 'away', 'status', 'pending', 'at', to_jsonb(now()));
  end if;
  return new;
end $$;

drop trigger if exists docs_guard on public.docs;
create trigger docs_guard before insert or update on public.docs
  for each row execute function public.docs_guard();

-- 5. Who can do what.
alter table public.docs enable row level security;
alter table public.admins enable row level security;

drop policy if exists "anyone reads" on public.docs;
drop policy if exists "organiser does anything" on public.docs;
drop policy if exists "anyone saves live counts" on public.docs;
drop policy if exists "anyone updates live counts" on public.docs;
drop policy if exists "anyone clears live counts" on public.docs;
drop policy if exists "anyone sends a result" on public.docs;
drop policy if exists "anyone resends an unconfirmed result" on public.docs;
drop policy if exists "organiser sees organisers" on public.admins;

create policy "anyone reads" on public.docs for select using (true);
create policy "organiser does anything" on public.docs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "anyone saves live counts" on public.docs for insert to anon, authenticated
  with check (path like 'live/%');
create policy "anyone updates live counts" on public.docs for update to anon, authenticated
  using (path like 'live/%') with check (path like 'live/%');
create policy "anyone clears live counts" on public.docs for delete to anon, authenticated
  using (path like 'live/%');
-- the public can send a match's result once, as 'pending'; after that only the organiser can change it
create policy "anyone sends a result" on public.docs for insert to anon, authenticated
  with check (path like 'scores/%' and data ->> 'status' = 'pending');
create policy "organiser sees organisers" on public.admins for select to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.docs to anon, authenticated;
revoke all on public.admins from anon;
grant select on public.admins to authenticated;
grant execute on function public.is_admin() to anon, authenticated;

-- 6. Live updates on everyone's screens.
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;
