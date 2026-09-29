
-- A/L Master — Live Friend Duels
-- Run AFTER supabase/schema.sql in Supabase SQL Editor.

create type duel_status as enum ('lobby','countdown','question','discuss','finished','abandoned');

create table if not exists duels (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  paper_id uuid not null references papers(id) on delete cascade,
  host_id uuid not null references profiles(id) on delete cascade,
  guest_id uuid references profiles(id) on delete set null,
  status duel_status not null default 'lobby',
  question_ids uuid[] not null,
  question_count int not null,
  seconds_per_question int not null default 45,
  discuss_seconds int not null default 20,
  current_index int not null default -1,
  phase_deadline timestamptz,
  question_started_at timestamptz,
  host_score int not null default 0,
  guest_score int not null default 0,
  host_answered boolean not null default false,
  guest_answered boolean not null default false,
  host_missed_streak int not null default 0,
  guest_missed_streak int not null default 0,
  discuss_extended boolean not null default false,
  host_ready boolean not null default false,
  guest_ready boolean not null default false,
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint duel_players_different check (guest_id is null or guest_id <> host_id),
  constraint duel_question_count check (question_count between 1 and 20),
  constraint duel_seconds check (seconds_per_question between 15 and 120)
);
create index if not exists duels_host_idx on duels(host_id, created_at desc);
create index if not exists duels_guest_idx on duels(guest_id, created_at desc);
create index if not exists duels_code_idx on duels(code);

create table if not exists duel_answers (
  id uuid primary key default gen_random_uuid(),
  duel_id uuid not null references duels(id) on delete cascade,
  question_id uuid not null references questions(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  selected answer_choice not null,
  is_correct boolean not null,
  ms_taken int not null,
  answered_at timestamptz not null default now(),
  unique (duel_id, question_id, user_id)
);
create index if not exists duel_answers_duel_idx on duel_answers(duel_id, question_id);

create table if not exists duel_messages (
  id uuid primary key default gen_random_uuid(),
  duel_id uuid not null references duels(id) on delete cascade,
  sender_id uuid not null references profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 300),
  question_index int,
  kind text not null default 'text' check (kind in ('text','reaction','system')),
  created_at timestamptz not null default now()
);
create index if not exists duel_messages_duel_idx on duel_messages(duel_id, created_at);

create table if not exists duel_message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references duel_messages(id) on delete cascade,
  reporter_id uuid not null references profiles(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  unique(message_id, reporter_id)
);

alter table duels enable row level security;
alter table duel_answers enable row level security;
alter table duel_messages enable row level security;
alter table duel_message_reports enable row level security;

drop policy if exists duel_players_select on duels;
create policy duel_players_select on duels for select using (auth.uid() = host_id or auth.uid() = guest_id);
drop policy if exists duel_answers_no_direct_read on duel_answers;
create policy duel_answers_no_direct_read on duel_answers for select using (false);
drop policy if exists duel_messages_select on duel_messages;
create policy duel_messages_select on duel_messages for select using (
  exists (select 1 from duels d where d.id=duel_id and (d.host_id=auth.uid() or d.guest_id=auth.uid()))
);
drop policy if exists duel_reports_insert on duel_message_reports;
create policy duel_reports_insert on duel_message_reports for insert with check (reporter_id=auth.uid());

create or replace function _duel_player(p_duel uuid)
returns duels language sql stable security definer set search_path=public as $$
  select d from duels d where d.id=p_duel and (d.host_id=auth.uid() or d.guest_id=auth.uid())
$$;

create or replace function _duel_code()
returns text language plpgsql volatile as $$
declare c text;
begin
  loop
    c := upper(substr(encode(gen_random_bytes(5),'hex'),1,6));
    exit when not exists(select 1 from duels where code=c);
  end loop;
  return c;
end $$;

create or replace function create_duel(p_paper_id uuid, p_question_count int default 10, p_seconds int default 45)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  qids uuid[]; did uuid; c text; n int;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if exists(select 1 from profiles where id=auth.uid() and is_suspended) then raise exception 'Your account is suspended'; end if;
  if p_question_count not between 5 and 20 then raise exception 'Question count must be 5–20'; end if;
  if p_seconds not between 15 and 120 then raise exception 'Time per question must be 15–120 seconds'; end if;
  select count(*) into n from questions where paper_id=p_paper_id;
  if n < 1 then raise exception 'This paper has no questions'; end if;
  p_question_count := least(p_question_count,n);
  select array_agg(id order by random()) into qids from (select id from questions where paper_id=p_paper_id order by random() limit p_question_count) s;
  c := _duel_code();
  insert into duels(code,paper_id,host_id,question_ids,question_count,seconds_per_question)
  values(c,p_paper_id,auth.uid(),qids,p_question_count,p_seconds)
  returning id into did;
  return jsonb_build_object('duel_id',did,'code',c);
end $$;

create or replace function join_duel(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if exists(select 1 from profiles where id=auth.uid() and is_suspended) then raise exception 'Your account is suspended'; end if;
  select * into d from duels where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Duel not found'; end if;
  if d.host_id=auth.uid() then return jsonb_build_object('duel_id',d.id,'code',d.code); end if;
  if d.guest_id is not null and d.guest_id<>auth.uid() then raise exception 'This duel already has two players'; end if;
  if d.status<>'lobby' then raise exception 'This duel has already started'; end if;
  if d.created_at < now()-interval '30 minutes' then raise exception 'This duel code has expired'; end if;
  update duels set guest_id=auth.uid() where id=d.id;
  return jsonb_build_object('duel_id',d.id,'code',d.code);
end $$;

create or replace function start_duel(p_duel uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare d duels;
begin
  select * into d from duels where id=p_duel for update;
  if d.host_id<>auth.uid() then raise exception 'Only the host can start'; end if;
  if d.guest_id is null then raise exception 'Waiting for your friend'; end if;
  if d.status<>'lobby' then return false; end if;
  update duels set status='countdown', phase_deadline=now()+interval '3 seconds' where id=p_duel;
  return true;
end $$;

create or replace function submit_duel_answer(p_duel uuid,p_question uuid,p_choice answer_choice)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; idx int; ms int; correct boolean; pts int; uid uuid:=auth.uid(); ishost boolean;
begin
  select * into d from duels where id=p_duel for update;
  if d.id is null or (d.host_id<>uid and d.guest_id<>uid) then raise exception 'Not a player in this duel'; end if;
  if d.status<>'question' then raise exception 'Answers are locked'; end if;
  idx:=d.current_index+1;
  if d.question_ids[idx]<>p_question then raise exception 'Wrong question'; end if;
  if now() > d.phase_deadline + interval '1 second' then raise exception 'Time is up'; end if;
  ishost := d.host_id=uid;
  if (ishost and d.host_answered) or ((not ishost) and d.guest_answered) then
    return jsonb_build_object('already',true);
  end if;
  ms:=greatest(0,least((extract(epoch from (now()-d.question_started_at))*1000)::int,d.seconds_per_question*1000+1000));
  select correct_answer=p_choice into correct from questions where id=p_question;
  pts:=case when correct then 10 + least(5,greatest(0, floor((d.seconds_per_question*1000-ms)::numeric/(d.seconds_per_question*200))::int)) else 0 end;
  insert into duel_answers(duel_id,question_id,user_id,selected,is_correct,ms_taken) values(p_duel,p_question,uid, p_choice,correct,ms);
  if ishost then
    update duels set host_answered=true,host_score=host_score+pts where id=p_duel;
  else
    update duels set guest_answered=true,guest_score=guest_score+pts where id=p_duel;
  end if;
  select * into d from duels where id=p_duel;
  if d.host_answered and d.guest_answered then
    update duels set status='discuss',phase_deadline=now()+make_interval(secs=>d.discuss_seconds),
      discuss_extended=false,host_ready=false,guest_ready=false where id=p_duel;
  end if;
  return jsonb_build_object('correct',correct,'points',pts);
end $$;

create or replace function advance_duel(p_duel uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; idx int; qid uuid; hmiss int; gmiss int;
begin
  select * into d from duels where id=p_duel for update;
  if d.id is null or (d.host_id<>auth.uid() and d.guest_id<>auth.uid()) then raise exception 'Not a player'; end if;
  if d.status='countdown' and now()>=d.phase_deadline then
    update duels set status='question',current_index=0,question_started_at=now(),phase_deadline=now()+make_interval(secs=>seconds_per_question),
      host_answered=false,guest_answered=false where id=p_duel;
  elsif d.status='question' and now()>=d.phase_deadline then
    hmiss:=case when d.host_answered then 0 else d.host_missed_streak+1 end;
    gmiss:=case when d.guest_answered then 0 else d.guest_missed_streak+1 end;
    if hmiss>=3 or gmiss>=3 then
      update duels set status='finished',finished_at=now(),host_missed_streak=hmiss,guest_missed_streak=gmiss where id=p_duel;
    else
      update duels set status='discuss',phase_deadline=now()+make_interval(secs=>d.discuss_seconds),
        discuss_extended=false,host_ready=false,guest_ready=false,host_missed_streak=hmiss,guest_missed_streak=gmiss where id=p_duel;
    end if;
  elsif d.status='discuss' and (now()>=d.phase_deadline or (d.host_ready and d.guest_ready)) then
    idx:=d.current_index+1;
    if idx>=d.question_count then
      update duels set status='finished',finished_at=now() where id=p_duel;
    else
      update duels set status='question',current_index=idx,question_started_at=now(),
        phase_deadline=now()+make_interval(secs=>seconds_per_question),host_answered=false,guest_answered=false,
        discuss_extended=false,host_ready=false,guest_ready=false where id=p_duel;
    end if;
  end if;
  return get_duel_state(p_duel);
end $$;

create or replace function duel_ready(p_duel uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare d duels;
begin
 select * into d from duels where id=p_duel for update;
 if d.host_id<>auth.uid() and d.guest_id<>auth.uid() then raise exception 'Not a player'; end if;
 if d.status<>'discuss' then return false; end if;
 if d.host_id=auth.uid() then update duels set host_ready=true where duels.id=p_duel;
 else update duels set guest_ready=true where duels.id=p_duel; end if;
 return true;
end $$;

create or replace function extend_discuss(p_duel uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare d duels;
begin
 select * into d from duels where id=p_duel for update;
 if d.host_id<>auth.uid() and d.guest_id<>auth.uid() then raise exception 'Not a player'; end if;
 if d.status<>'discuss' or d.discuss_extended then return false; end if;
 update duels set phase_deadline=phase_deadline+interval '10 seconds',discuss_extended=true where id=p_duel;
 return true;
end $$;

create or replace function get_duel_state(p_duel uuid)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare d duels; q questions; qnext questions; me jsonb; opp jsonb; myid uuid:=auth.uid();
begin
 select * into d from duels where id=p_duel and (host_id=myid or guest_id=myid);
 if not found then raise exception 'Duel not found'; end if;
 if d.status='question' and d.current_index>=0 then select * into q from questions where id=d.question_ids[d.current_index+1]; if d.current_index+1 < d.question_count then select * into qnext from questions where id=d.question_ids[d.current_index+2]; end if; end if;
 select jsonb_build_object('id',id,'name',coalesce(display_name,full_name,'Player'),'avatar',avatar_url) into me from profiles where id=myid;
 select jsonb_build_object('id',id,'name',coalesce(display_name,full_name,'Player'),'avatar',avatar_url) into opp from profiles where id=case when d.host_id=myid then d.guest_id else d.host_id end;
 return jsonb_build_object(
   'id',d.id,'code',d.code,'paper_id',d.paper_id,'host_id',d.host_id,'guest_id',d.guest_id,'status',d.status,'question_count',d.question_count,
   'seconds',d.seconds_per_question,'discuss_seconds',d.discuss_seconds,'current_index',d.current_index,
   'deadline',d.phase_deadline,'server_now',now(),'host_score',d.host_score,'guest_score',d.guest_score,
   'host_answered',d.host_answered,'guest_answered',d.guest_answered,'host_ready',d.host_ready,'guest_ready',d.guest_ready,
   'me',me,'opponent',opp,
   'question',case when q.id is null then null else jsonb_build_object('id',q.id,'number',q.question_number,'image',q.question_image_url) end,'next_image',case when qnext.id is null then null else qnext.question_image_url end
 );
end $$;

create or replace function get_duel_reveal(p_duel uuid)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare d duels; qid uuid; q questions; ha duel_answers; ga duel_answers; myid uuid:=auth.uid();
begin
 select * into d from duels where id=p_duel and (host_id=myid or guest_id=myid);
 if not found then raise exception 'Duel not found'; end if;
 if d.status not in ('discuss','finished') then raise exception 'Reveal is not ready'; end if;
 qid:=d.question_ids[d.current_index+1];
 select * into q from questions where id=qid;
 select * into ha from duel_answers where duel_id=d.id and question_id=qid and user_id=d.host_id;
 select * into ga from duel_answers where duel_id=d.id and question_id=qid and user_id=d.guest_id;
 return jsonb_build_object('question_id',qid,'correct',q.correct_answer,'review',q.review_text,'review_image',q.review_image_url,
   'host',case when ha.id is null then null else jsonb_build_object('choice',ha.selected,'correct',ha.is_correct,'ms',ha.ms_taken) end,
   'guest',case when ga.id is null then null else jsonb_build_object('choice',ga.selected,'correct',ga.is_correct,'ms',ga.ms_taken) end);
end $$;

create or replace function send_duel_message(p_duel uuid,p_body text,p_kind text default 'text')
returns uuid language plpgsql security definer set search_path=public as $$
declare d duels; mid uuid; clean text:=btrim(p_body);
begin
 select * into d from duels where id=p_duel and (host_id=auth.uid() or guest_id=auth.uid());
 if not found then raise exception 'Not a player'; end if;
 if d.status not in ('lobby','discuss','finished') then raise exception 'Chat is locked during the question'; end if;
 if exists(select 1 from profiles where id=auth.uid() and is_suspended) then raise exception 'Chat unavailable'; end if;
 if clean='' or char_length(clean)>300 then raise exception 'Message must be 1–300 characters'; end if;
 if clean ~* '(https?://|www\.|[[:alnum:]_-]+\.(com|net|org|lk)(/|$))' then raise exception 'Links are not allowed'; end if;
 if exists(select 1 from app_settings where key='duel_chat_enabled' and value='false'::jsonb) then raise exception 'Duel chat is currently off'; end if;
 if exists(select 1 from duel_messages where duel_id=p_duel and sender_id=auth.uid() and created_at>now()-interval '1 second') then raise exception 'Please slow down'; end if;
 if exists(select 1 from duel_messages where duel_id=p_duel and sender_id=auth.uid() and created_at>now()-interval '1 minute' group by sender_id having count(*)>=20) then raise exception 'Chat rate limit reached'; end if;
 insert into duel_messages(duel_id,sender_id,body,question_index,kind) values(p_duel,auth.uid(),clean,d.current_index,p_kind) returning id into mid;
 return mid;
end $$;

create or replace function get_duel_messages(p_duel uuid)
returns setof duel_messages language sql security definer stable set search_path=public as $$
 select m.* from duel_messages m join duels d on d.id=m.duel_id
 where m.duel_id=p_duel and (d.host_id=auth.uid() or d.guest_id=auth.uid()) order by m.created_at asc
$$;

create or replace function report_duel_message(p_message uuid,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
 if not exists(select 1 from duel_messages m join duels d on d.id=m.duel_id where m.id=p_message and (d.host_id=auth.uid() or d.guest_id=auth.uid())) then raise exception 'Message not found'; end if;
 insert into duel_message_reports(message_id,reporter_id,reason) values(p_message,auth.uid(),left(p_reason,200))
 on conflict do nothing returning id into rid;
 return rid;
end $$;

create or replace function create_rematch(p_duel uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; q jsonb;
begin
 select * into d from duels where id=p_duel and (host_id=auth.uid() or guest_id=auth.uid());
 if not found or d.status<>'finished' then raise exception 'Rematch is unavailable'; end if;
 select create_duel(d.paper_id,d.question_count,d.seconds_per_question) into q;
 return q;
end $$;

create or replace function cleanup_duels()
returns int language plpgsql security definer set search_path=public as $$
declare n int;
begin
 delete from duels where (status='lobby' and created_at<now()-interval '30 minutes')
    or (finished_at is not null and finished_at<now()-interval '7 days');
 get diagnostics n=ROW_COUNT;
 return n;
end $$;

do $$ begin
  alter publication supabase_realtime add table duels;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table duel_messages;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- Optional global switch:
-- insert into app_settings(key,value) values ('duel_chat_enabled','true'::jsonb)
-- on conflict (key) do nothing;
