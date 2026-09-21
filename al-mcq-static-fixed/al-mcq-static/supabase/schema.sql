-- =====================================================================
-- A/L MCQ Platform — static (no-server) edition
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Everything that used to need a service-role key now lives in RLS
-- policies and SECURITY DEFINER functions instead, because there is no
-- server left to hold that key.
-- =====================================================================

create extension if not exists pgcrypto;

create type user_role     as enum ('student','teacher','admin');
create type answer_choice as enum ('A','B','C','D','E');
create type paper_type    as enum ('past','topic','model','teacher');
create type exam_mode     as enum ('exam','practice');

create table profiles (
  id                    uuid primary key references auth.users on delete cascade,
  full_name             text,
  display_name          text,
  avatar_url            text,
  role                  user_role not null default 'student',
  hide_from_leaderboard boolean   not null default false,
  is_suspended          boolean   not null default false,
  created_at            timestamptz default now()
);

create table papers (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  subject          text not null check (subject in ('physics','chemistry')),
  year             int,
  paper_type       paper_type not null default 'past',
  description      text,
  duration_minutes int  not null default 60,
  total_questions  int  not null default 50,
  is_published     boolean not null default false,
  created_by       uuid references profiles(id),
  created_at       timestamptz default now()
);
create index on papers (subject, paper_type, is_published);

create table questions (
  id                 uuid primary key default gen_random_uuid(),
  paper_id           uuid not null references papers(id) on delete cascade,
  question_number    int  not null,
  question_image_url text not null,
  correct_answer     answer_choice not null,
  topic              text,
  subtopic           text,
  marks              int not null default 1,
  review_text        text,
  review_image_url   text,
  created_at         timestamptz default now(),
  unique (paper_id, question_number)
);
create index on questions (paper_id, question_number);

create table attempts (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid references profiles(id) on delete cascade,
  paper_id          uuid not null references papers(id) on delete cascade,
  mode              exam_mode not null default 'exam',
  started_at        timestamptz default now(),
  expires_at        timestamptz not null,
  completed_at      timestamptz,
  score             int, correct_count int, wrong_count int,
  unanswered_count  int, percentage numeric(5,2), time_taken_seconds int
);
create index on attempts (user_id, completed_at desc);
create index on attempts (paper_id);

create table attempt_answers (
  id                 uuid primary key default gen_random_uuid(),
  attempt_id         uuid not null references attempts(id) on delete cascade,
  question_id        uuid not null references questions(id) on delete cascade,
  selected_answer    answer_choice,
  is_correct         boolean,
  time_spent_seconds int,
  answered_at        timestamptz default now(),
  unique (attempt_id, question_id)
);
create index on attempt_answers (question_id);

create table user_statistics (
  user_id           uuid primary key references profiles(id) on delete cascade,
  total_attempts    int default 0, completed_papers int default 0,
  questions_answered int default 0, correct_answers int default 0,
  wrong_answers     int default 0, accuracy numeric(5,2) default 0,
  total_points      int default 0, weekly_points int default 0,
  monthly_points    int default 0, current_streak int default 0,
  longest_streak    int default 0, last_active_date date,
  updated_at        timestamptz default now()
);

create table leaderboard_entries (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id) on delete cascade,
  board_type text not null,
  subject    text, period_key text,
  points     int default 0, accuracy numeric(5,2), papers_completed int default 0,
  rank       int, updated_at timestamptz default now(),
  unique (user_id, board_type, subject, period_key)
);
create index on leaderboard_entries (board_type, period_key, points desc);

create table advertisements (
  id          uuid primary key default gen_random_uuid(),
  title       text, image_url text not null, link_url text,
  placement   text not null,
  start_date  date, end_date date,
  is_active   boolean default true, priority int default 0,
  impressions int default 0, clicks int default 0,
  created_at  timestamptz default now()
);

create table ad_events (
  id         uuid primary key default gen_random_uuid(),
  ad_id      uuid references advertisements(id) on delete cascade,
  event_type text not null check (event_type in ('impression','click')),
  placement  text, created_at timestamptz default now()
);
create index on ad_events (ad_id, event_type, created_at desc);

create table app_settings (
  key text primary key,
  value jsonb not null
);

insert into app_settings (key, value) values
  ('points_correct',           '2'::jsonb),
  ('points_complete_paper',    '10'::jsonb),
  ('points_perfect_bonus',     '25'::jsonb),
  ('accuracy_board_min_papers','5'::jsonb),
  ('leaderboard_name_mode',    '"first_initial"'::jsonb),
  ('adsense_enabled',          'true'::jsonb),
  ('adsense_slot_dashboard',   'null'::jsonb),
  ('adsense_slot_paper_top',   'null'::jsonb),
  ('adsense_slot_result',      'null'::jsonb),
  ('adsense_slot_sidebar',     'null'::jsonb)
on conflict (key) do nothing;

-- =====================================================================
-- Auto-create a profile the moment someone signs in with Google.
-- This replaces the /auth/callback server route from the Next.js build —
-- there is no server here, so the database does it via trigger instead.
-- =====================================================================
create or replace function handle_new_user()
returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_name text;
begin
  v_name := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', 'Student');

  insert into profiles (id, full_name, display_name, avatar_url)
  values (new.id, v_name, split_part(v_name, ' ', 1), new.raw_user_meta_data->>'avatar_url')
  on conflict (id) do nothing;

  insert into user_statistics (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table profiles            enable row level security;
alter table papers              enable row level security;
alter table questions           enable row level security;
alter table attempts            enable row level security;
alter table attempt_answers     enable row level security;
alter table user_statistics     enable row level security;
alter table leaderboard_entries enable row level security;
alter table advertisements      enable row level security;
alter table ad_events           enable row level security;
alter table app_settings        enable row level security;

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role in ('admin','teacher'));
$$;

create policy "read own profile"   on profiles for select using (id = auth.uid() or is_staff());
create policy "update own profile" on profiles for update using (id = auth.uid());
create policy "staff manage profiles" on profiles for all using (is_staff());

create policy "read published papers" on papers for select using (is_published or is_staff());
create policy "staff write papers" on papers for all using (is_staff());

-- Students get NO select policy on questions at all. The exam page reads
-- only id/question_number/question_image_url/topic — see the note on the
-- get_exam_questions() function below for how that is enforced without a
-- server to filter columns for us.
create policy "staff manage questions" on questions for all using (is_staff());

create policy "own attempts" on attempts for all using (user_id = auth.uid());
create policy "staff read attempts" on attempts for select using (is_staff());

create policy "own answers" on attempt_answers for all using (
  exists (select 1 from attempts a where a.id = attempt_id and a.user_id = auth.uid())
);
create policy "staff read answers" on attempt_answers for select using (is_staff());

create policy "read stats"        on user_statistics     for select using (true);
create policy "staff write stats" on user_statistics     for all    using (is_staff());
create policy "read leaderboard"  on leaderboard_entries for select using (true);
create policy "staff write lb"    on leaderboard_entries for all    using (is_staff());

create policy "read active ads" on advertisements for select using (is_active or is_staff());
create policy "staff write ads" on advertisements for all using (is_staff());
create policy "staff read ad events" on ad_events for select using (is_staff());

create policy "read settings"  on app_settings for select using (true);
create policy "staff settings" on app_settings for all    using (is_staff());

-- =====================================================================
-- The functions that stand in for a server
-- =====================================================================

-- Start (or resume) an attempt. SECURITY DEFINER so it can insert past the
-- RLS check that would otherwise require the row to already reference the
-- caller — the same effect as the old POST /api/attempts route.
create or replace function start_attempt(p_paper_id uuid, p_mode exam_mode default 'exam')
returns table (attempt_id uuid, resumed boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_duration int;
  v_published boolean;
  v_existing uuid;
  v_new uuid;
begin
  select duration_minutes, is_published into v_duration, v_published
    from papers where id = p_paper_id;

  if not v_published then raise exception 'This paper is not available.'; end if;

  select id into v_existing from attempts
   where user_id = auth.uid() and paper_id = p_paper_id
     and completed_at is null and expires_at > now()
   limit 1;

  if v_existing is not null then
    return query select v_existing, true;
    return;
  end if;

  insert into attempts (user_id, paper_id, mode, expires_at)
  values (auth.uid(), p_paper_id, p_mode, now() + (v_duration || ' minutes')::interval)
  returning id into v_new;

  return query select v_new, false;
end;
$$;

-- Returns ONLY the columns a student is allowed to see before submitting.
-- This is the column-level equivalent of the old service-role select list
-- in the Next.js exam page — the database enforces it here instead.
create or replace function get_exam_questions(p_attempt_id uuid)
returns table (id uuid, question_number int, question_image_url text, topic text)
language plpgsql security definer set search_path = public as $$
declare
  v_paper uuid;
begin
  select paper_id into v_paper from attempts
   where id = p_attempt_id and user_id = auth.uid();

  if v_paper is null then raise exception 'Attempt not found.'; end if;

  return query
    select q.id, q.question_number, q.question_image_url, q.topic
      from questions q where q.paper_id = v_paper
     order by q.question_number;
end;
$$;

-- Save one answer. Rejects writes to someone else's attempt or a closed one.
create or replace function save_answer(p_attempt_id uuid, p_question_id uuid, p_selected answer_choice, p_time_spent int default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid; v_completed timestamptz; v_expires timestamptz;
begin
  select user_id, completed_at, expires_at into v_owner, v_completed, v_expires
    from attempts where id = p_attempt_id;

  if v_owner is distinct from auth.uid() then raise exception 'Not your attempt.'; end if;
  if v_completed is not null then raise exception 'Already submitted.'; end if;
  if v_expires < now() - interval '30 seconds' then raise exception 'Time is up.'; end if;

  insert into attempt_answers (attempt_id, question_id, selected_answer, time_spent_seconds)
  values (p_attempt_id, p_question_id, p_selected, p_time_spent)
  on conflict (attempt_id, question_id)
  do update set selected_answer = excluded.selected_answer,
                time_spent_seconds = excluded.time_spent_seconds;
end;
$$;

-- Practice mode: reveal one answer, only after a selection exists for it.
create or replace function reveal_answer(p_attempt_id uuid, p_question_id uuid)
returns table (correct answer_choice, is_correct boolean, review_text text, review_image_url text)
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid; v_mode exam_mode; v_selected answer_choice;
begin
  select user_id, mode into v_owner, v_mode from attempts where id = p_attempt_id;
  if v_owner is distinct from auth.uid() then raise exception 'Not your attempt.'; end if;
  if v_mode <> 'practice' then raise exception 'Not available in exam mode.'; end if;

  select selected_answer into v_selected from attempt_answers
   where attempt_id = p_attempt_id and question_id = p_question_id;
  if v_selected is null then raise exception 'Choose an answer first.'; end if;

  return query
    select q.correct_answer, v_selected = q.correct_answer, q.review_text, q.review_image_url
      from questions q where q.id = p_question_id;
end;
$$;

-- Grade, close the attempt, update statistics and leaderboards. This is the
-- one function every layer of secrecy in this app exists to protect —
-- nothing else may compare selected_answer to correct_answer.
create or replace function submit_attempt(p_attempt_id uuid)
returns table (score int, correct_count int, wrong_count int, unanswered_count int, percentage numeric, time_taken_seconds int)
language plpgsql security definer set search_path = public as $$
declare
  v_attempt attempts%rowtype;
  v_total int; v_correct int; v_answered int; v_seconds int; v_points int;
  v_pts_correct int := (select (value)::text::int from app_settings where key='points_correct');
  v_pts_paper   int := (select (value)::text::int from app_settings where key='points_complete_paper');
  v_pts_perfect int := (select (value)::text::int from app_settings where key='points_perfect_bonus');
begin
  select * into v_attempt from attempts where id = p_attempt_id;
  if v_attempt.user_id is distinct from auth.uid() then raise exception 'Not your attempt.'; end if;
  if v_attempt.completed_at is not null then raise exception 'already submitted'; end if;

  update attempt_answers aa set is_correct = (aa.selected_answer = q.correct_answer)
    from questions q where q.id = aa.question_id and aa.attempt_id = p_attempt_id;

  select count(*) into v_total from questions where paper_id = v_attempt.paper_id;
  select count(*) filter (where is_correct), count(*) filter (where selected_answer is not null)
    into v_correct, v_answered from attempt_answers where attempt_id = p_attempt_id;

  v_seconds := greatest(0, extract(epoch from (now() - v_attempt.started_at))::int);

  update attempts set completed_at = now(), score = v_correct, correct_count = v_correct,
    wrong_count = v_answered - v_correct, unanswered_count = v_total - v_answered,
    percentage = case when v_total = 0 then 0 else round((v_correct::numeric / v_total) * 100, 2) end,
    time_taken_seconds = v_seconds
  where id = p_attempt_id;

  v_points := v_correct * v_pts_correct + v_pts_paper
            + case when v_correct = v_total and v_total > 0 then v_pts_perfect else 0 end;

  insert into user_statistics (user_id) values (v_attempt.user_id) on conflict (user_id) do nothing;

  update user_statistics s set
    total_attempts = s.total_attempts + 1, completed_papers = s.completed_papers + 1,
    questions_answered = s.questions_answered + v_answered,
    correct_answers = s.correct_answers + v_correct,
    wrong_answers = s.wrong_answers + (v_answered - v_correct),
    accuracy = case when (s.questions_answered + v_answered) = 0 then 0
      else round(((s.correct_answers + v_correct)::numeric / (s.questions_answered + v_answered)) * 100, 2) end,
    total_points = s.total_points + v_points, weekly_points = s.weekly_points + v_points,
    monthly_points = s.monthly_points + v_points,
    current_streak = case when s.last_active_date = current_date then s.current_streak
                          when s.last_active_date = current_date - 1 then s.current_streak + 1 else 1 end,
    longest_streak = greatest(s.longest_streak,
      case when s.last_active_date = current_date then s.current_streak
           when s.last_active_date = current_date - 1 then s.current_streak + 1 else 1 end),
    last_active_date = current_date, updated_at = now()
  where s.user_id = v_attempt.user_id;

  insert into leaderboard_entries (user_id, board_type, subject, period_key, points, accuracy, papers_completed)
  select v_attempt.user_id, 'all_time', null, 'all', s.total_points, s.accuracy, s.completed_papers
    from user_statistics s where s.user_id = v_attempt.user_id
  on conflict (user_id, board_type, subject, period_key) do update
    set points = excluded.points, accuracy = excluded.accuracy, papers_completed = excluded.papers_completed, updated_at = now();

  insert into leaderboard_entries (user_id, board_type, subject, period_key, points)
  values (v_attempt.user_id, 'weekly', null, to_char(now(), 'IYYY-"W"IW'), v_points)
  on conflict (user_id, board_type, subject, period_key) do update
    set points = leaderboard_entries.points + excluded.points, updated_at = now();

  insert into leaderboard_entries (user_id, board_type, subject, period_key, points)
  values (v_attempt.user_id, 'monthly', null, to_char(now(), 'YYYY-MM'), v_points)
  on conflict (user_id, board_type, subject, period_key) do update
    set points = leaderboard_entries.points + excluded.points, updated_at = now();

  return query select a.score, a.correct_count, a.wrong_count, a.unanswered_count, a.percentage, a.time_taken_seconds
    from attempts a where a.id = p_attempt_id;
end;
$$;

-- Ad click/impression counters, callable from the browser with the anon key.
create or replace function track_ad_event(p_ad_id uuid, p_type text, p_placement text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_type not in ('impression','click') then raise exception 'unknown event type'; end if;
  insert into ad_events (ad_id, event_type, placement) values (p_ad_id, p_type, p_placement);
  if p_type = 'click' then update advertisements set clicks = clicks + 1 where id = p_ad_id;
  else update advertisements set impressions = impressions + 1 where id = p_ad_id; end if;
end;
$$;

-- Weekly/monthly point reset. Call this from the Supabase pg_cron
-- extension (see README) since there is no Vercel Cron in a static site.
create or replace function reset_period_points(p_period text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_period = 'weekly' then update user_statistics set weekly_points = 0;
  elsif p_period = 'monthly' then update user_statistics set monthly_points = 0;
  end if;
end;
$$;

-- ---------------------------------------------- analytics helper views
create view question_difficulty as
select q.id, q.paper_id, q.question_number, q.topic, p.subject, p.title as paper_title,
       count(aa.id) filter (where aa.selected_answer is not null) as attempts,
       round(100.0 * count(aa.id) filter (where aa.is_correct)
             / nullif(count(aa.id) filter (where aa.selected_answer is not null), 0), 1) as correct_pct
from questions q join papers p on p.id = q.paper_id
left join attempt_answers aa on aa.question_id = q.id
group by q.id, q.paper_id, q.question_number, q.topic, p.subject, p.title;

create view topic_performance as
select a.user_id, p.subject, q.topic,
       count(*) as answered,
       count(*) filter (where aa.is_correct) as correct,
       round(100.0 * count(*) filter (where aa.is_correct) / nullif(count(*), 0), 1) as accuracy
from attempt_answers aa
join attempts a on a.id = aa.attempt_id and a.completed_at is not null
join questions q on q.id = aa.question_id
join papers p on p.id = q.paper_id
where q.topic is not null
group by a.user_id, p.subject, q.topic;

create view house_ad_performance as
select a.id, a.title, a.placement, a.is_active,
       count(*) filter (where e.event_type = 'impression') as impressions,
       count(*) filter (where e.event_type = 'click')      as clicks,
       round(100.0 * count(*) filter (where e.event_type = 'click')
             / nullif(count(*) filter (where e.event_type = 'impression'), 0), 2) as ctr
from advertisements a
left join ad_events e on e.ad_id = a.id
group by a.id, a.title, a.placement, a.is_active;

-- =====================================================================
-- Storage buckets: create "questions", "reviews", "ads" in the Storage
-- tab first (all Public), then run this.
-- =====================================================================
create policy "public read questions" on storage.objects for select using (bucket_id = 'questions');
create policy "staff write questions" on storage.objects for all
  using (bucket_id = 'questions' and is_staff()) with check (bucket_id = 'questions' and is_staff());

create policy "public read reviews" on storage.objects for select using (bucket_id = 'reviews');
create policy "staff write reviews" on storage.objects for all
  using (bucket_id = 'reviews' and is_staff()) with check (bucket_id = 'reviews' and is_staff());

create policy "public read ads" on storage.objects for select using (bucket_id = 'ads');
create policy "staff write ads" on storage.objects for all
  using (bucket_id = 'ads' and is_staff()) with check (bucket_id = 'ads' and is_staff());
