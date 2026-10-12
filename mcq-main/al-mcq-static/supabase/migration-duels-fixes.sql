-- A/L Master — duel v3 + v4 in ONE file. Run this once in the Supabase SQL Editor (after migration-duels.sql and migration-duels-fixes.sql). Safe to re-run.

-- A/L Master — duel v3: change answer + Lock, manual Next, leave_duel, joinable rematch.
-- Run AFTER migration-duels.sql and migration-duels-fixes.sql. Safe to re-run.

-- 0a. Your database may already have older versions of some of these functions with a different
--     return type (Postgres refuses to replace those), so remove them first. They are re-created below.
drop function if exists _duel_record(uuid, uuid, answer_choice, int);
drop function if exists _duel_keys(uuid);
drop function if exists save_duel_choice(uuid, uuid, answer_choice);
drop function if exists submit_duel_answer(uuid, uuid, answer_choice);
drop function if exists advance_duel(uuid);
drop function if exists get_duel_state(uuid);
drop function if exists leave_duel(uuid);
drop function if exists create_rematch(uuid);
drop function if exists create_duel(uuid, int, int);

-- 0b. The real answer key. Your admin panel stores it in questions.correct_answers (a list: one or more
--     correct letters, all five = "any answer", empty = voided). The old single questions.correct_answer
--     column is only used as a fallback when that list is empty.
create or replace function _duel_keys(p_question uuid)
returns text[] language sql stable security definer set search_path=public as $$
  select case
    when q.correct_answers is not null and cardinality(q.correct_answers) > 0 then q.correct_answers::text[]
    when q.correct_answer is not null then array[q.correct_answer::text]
    else '{}'::text[] end
  from questions q where q.id = p_question
$$;
-- must not be callable from the browser (it would leak answers)
revoke all on function _duel_keys(uuid) from public, anon, authenticated;

-- 0. New columns ------------------------------------------------------------
alter table duels add column if not exists host_choice answer_choice;   -- unlocked pick (changeable)
alter table duels add column if not exists guest_choice answer_choice;
alter table duels add column if not exists rematch_code text;

-- Discussion no longer auto-advances after 20s. Players tap "Next question".
-- discuss_seconds is now only a safety cap so a duel can't hang forever if someone walks away.
-- Your database has a check constraint on discuss_seconds (it isn't in the original migration), so widen it first.
alter table duels drop constraint if exists duel_discuss_seconds;
alter table duels add constraint duel_discuss_seconds check (discuss_seconds between 5 and 900);
alter table duels alter column discuss_seconds set default 300;
update duels set discuss_seconds = 300 where status in ('lobby','countdown','question','discuss');

-- 1. Internal helper: record a locked answer + score it ----------------------
create or replace function _duel_record(p_duel uuid, p_uid uuid, p_choice answer_choice, p_ms int)
returns void language plpgsql security definer set search_path=public as $$
declare d duels; qid uuid; keys text[]; correct boolean; pts int; ishost boolean;
begin
  select * into d from duels where id=p_duel;
  qid := d.question_ids[d.current_index+1];
  ishost := d.host_id = p_uid;
  keys := _duel_keys(qid);
  correct := (p_choice is not null and cardinality(keys) > 0 and p_choice::text = any(keys));
  pts := case when correct then 10 + least(5, greatest(0,
           floor((d.seconds_per_question*1000-p_ms)::numeric/(d.seconds_per_question*200))::int)) else 0 end;

  insert into duel_answers(duel_id,question_id,user_id,selected,is_correct,ms_taken)
  values(p_duel,qid,p_uid,p_choice,correct,p_ms)
  on conflict (duel_id,question_id,user_id) do nothing;

  if ishost then
    update duels set host_answered=true, host_choice=p_choice, host_score=host_score+pts, host_missed_streak=0 where id=p_duel;
  else
    update duels set guest_answered=true, guest_choice=p_choice, guest_score=guest_score+pts, guest_missed_streak=0 where id=p_duel;
  end if;
end $$;
-- Must not be callable from the browser (it would let someone score themselves).
revoke all on function _duel_record(uuid,uuid,answer_choice,int) from public, anon, authenticated;

-- 2. Save an UNLOCKED pick (changeable any number of times before Lock) -------
create or replace function save_duel_choice(p_duel uuid, p_question uuid, p_choice answer_choice)
returns boolean language plpgsql security definer set search_path=public as $$
declare d duels; uid uuid := auth.uid(); ishost boolean;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  select * into d from duels where id=p_duel for update;
  if not found then raise exception 'Duel not found'; end if;
  if d.host_id is distinct from uid and d.guest_id is distinct from uid then raise exception 'Not a player in this duel'; end if;
  if d.status<>'question' then return false; end if;
  if d.question_ids[d.current_index+1] is distinct from p_question then return false; end if;
  ishost := d.host_id = uid;
  if (ishost and d.host_answered) or ((not ishost) and d.guest_answered) then return false; end if;   -- already locked
  if ishost then update duels set host_choice=p_choice where id=p_duel;
  else update duels set guest_choice=p_choice where id=p_duel; end if;
  return true;
end $$;

-- 3. LOCK the answer (final) ---------------------------------------------------
create or replace function submit_duel_answer(p_duel uuid, p_question uuid, p_choice answer_choice)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; ms int; uid uuid := auth.uid(); ishost boolean; q_correct answer_choice;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  if p_choice is null then raise exception 'Please select an answer'; end if;
  select * into d from duels where id=p_duel for update;
  if not found then raise exception 'Duel not found'; end if;
  if d.host_id is distinct from uid and d.guest_id is distinct from uid then raise exception 'Not a player in this duel'; end if;
  if d.status<>'question' then raise exception 'Answers are locked'; end if;
  if d.question_ids[d.current_index+1] is distinct from p_question then raise exception 'Wrong question'; end if;
  if now() > d.phase_deadline + interval '1 second' then raise exception 'Time is up'; end if;
  ishost := d.host_id = uid;
  if (ishost and d.host_answered) or ((not ishost) and d.guest_answered) then
    return jsonb_build_object('already',true);
  end if;
  -- A question with no answer key configured no longer blocks the player: it just scores 0 for both.
  ms := greatest(0, least((extract(epoch from (now()-d.question_started_at))*1000)::int, d.seconds_per_question*1000+1000));
  perform _duel_record(p_duel, uid, p_choice, ms);

  select * into d from duels where id=p_duel;
  if d.host_answered and d.guest_answered then
    update duels set status='discuss', phase_deadline=now()+make_interval(secs=>d.discuss_seconds),
      discuss_extended=false, host_ready=false, guest_ready=false where id=p_duel;
  end if;
  return jsonb_build_object('locked',true,'ms_taken',ms);   -- correctness is NOT returned; revealed in the discuss phase
end $$;

-- 4. Advance: time-out auto-locks any unlocked pick; discussion needs both "Next" taps
create or replace function advance_duel(p_duel uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; idx int; hmiss int; gmiss int; full_ms int;
begin
  select * into d from duels where id=p_duel for update;
  if d.id is null or (d.host_id<>auth.uid() and d.guest_id<>auth.uid()) then raise exception 'Not a player'; end if;

  if d.status='countdown' and now()>=d.phase_deadline then
    update duels set status='question', current_index=0, question_started_at=now(),
      phase_deadline=now()+make_interval(secs=>seconds_per_question),
      host_answered=false, guest_answered=false, host_choice=null, guest_choice=null where id=p_duel;

  elsif d.status='question' and now()>=d.phase_deadline then
    full_ms := d.seconds_per_question*1000;
    -- time is up: whatever a player had selected but not locked is locked for them
    if not d.host_answered and d.host_choice is not null then perform _duel_record(p_duel, d.host_id, d.host_choice, full_ms); end if;
    if not d.guest_answered and d.guest_choice is not null and d.guest_id is not null then perform _duel_record(p_duel, d.guest_id, d.guest_choice, full_ms); end if;
    select * into d from duels where id=p_duel;
    hmiss := case when d.host_answered then 0 else d.host_missed_streak+1 end;
    gmiss := case when d.guest_answered then 0 else d.guest_missed_streak+1 end;
    if hmiss>=3 or gmiss>=3 then
      update duels set status='finished', finished_at=now(), host_missed_streak=hmiss, guest_missed_streak=gmiss where id=p_duel;
    else
      update duels set status='discuss', phase_deadline=now()+make_interval(secs=>d.discuss_seconds),
        discuss_extended=false, host_ready=false, guest_ready=false,
        host_missed_streak=hmiss, guest_missed_streak=gmiss where id=p_duel;
    end if;

  elsif d.status='discuss' and (now()>=d.phase_deadline or (d.host_ready and d.guest_ready)) then
    idx := d.current_index+1;
    if idx>=d.question_count then
      update duels set status='finished', finished_at=now() where id=p_duel;
    else
      update duels set status='question', current_index=idx, question_started_at=now(),
        phase_deadline=now()+make_interval(secs=>seconds_per_question),
        host_answered=false, guest_answered=false, host_choice=null, guest_choice=null,
        discuss_extended=false, host_ready=false, guest_ready=false where id=p_duel;
    end if;
  end if;
  return get_duel_state(p_duel);
end $$;

-- 5. State: also return my own (unlocked or locked) pick + rematch code --------
create or replace function get_duel_state(p_duel uuid)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare d duels; q questions; qnext questions; me jsonb; opp jsonb; myid uuid := auth.uid();
begin
  select * into d from duels where id=p_duel and (host_id=myid or guest_id=myid);
  if not found then raise exception 'Duel not found'; end if;
  if d.status='question' and d.current_index>=0 then
    select * into q from questions where id=d.question_ids[d.current_index+1];
    if d.current_index+1 < d.question_count then select * into qnext from questions where id=d.question_ids[d.current_index+2]; end if;
  end if;
  select jsonb_build_object('id',id,'name',coalesce(display_name,full_name,'Player'),'avatar',avatar_url) into me from profiles where id=myid;
  select jsonb_build_object('id',id,'name',coalesce(display_name,full_name,'Player'),'avatar',avatar_url) into opp
    from profiles where id=case when d.host_id=myid then d.guest_id else d.host_id end;
  return jsonb_build_object(
    'id',d.id,'code',d.code,'paper_id',d.paper_id,'host_id',d.host_id,'guest_id',d.guest_id,'status',d.status,'question_count',d.question_count,
    'seconds',d.seconds_per_question,'discuss_seconds',d.discuss_seconds,'current_index',d.current_index,
    'deadline',d.phase_deadline,'server_now',now(),'host_score',d.host_score,'guest_score',d.guest_score,
    'host_answered',d.host_answered,'guest_answered',d.guest_answered,'host_ready',d.host_ready,'guest_ready',d.guest_ready,
    'my_choice', case when d.host_id=myid then d.host_choice else d.guest_choice end,
    'rematch_code', d.rematch_code,
    'me',me,'opponent',opp,
    'question',case when q.id is null then null else jsonb_build_object('id',q.id,'number',q.question_number,'image',q.question_image_url) end,
    'next_image',case when qnext.id is null then null else qnext.question_image_url end);
end $$;

-- 6. Leave (the Leave button called this, but it was never defined) -------------
create or replace function leave_duel(p_duel uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare d duels;
begin
  select * into d from duels where id=p_duel for update;
  if d.id is null or (d.host_id is distinct from auth.uid() and d.guest_id is distinct from auth.uid()) then raise exception 'Not a player'; end if;
  if d.status in ('finished','abandoned') then return true; end if;
  if d.status='lobby' then
    if d.host_id=auth.uid() then delete from duels where id=p_duel;          -- host closes the lobby
    else update duels set guest_id=null where id=p_duel; end if;             -- guest just steps out
  else
    update duels set status='abandoned', finished_at=now() where id=p_duel;  -- ends for both
  end if;
  return true;
end $$;

-- 7. Rematch: the friend can now join it (before, only the clicker got a new room)
create or replace function create_rematch(p_duel uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; q jsonb;
begin
  select * into d from duels where id=p_duel and (host_id=auth.uid() or guest_id=auth.uid()) for update;
  if not found or d.status<>'finished' then raise exception 'Rematch is unavailable'; end if;
  if d.rematch_code is not null then
    return jsonb_build_object('code', d.rematch_code, 'duel_id', (select id from duels where code=d.rematch_code));
  end if;
  select create_duel(d.paper_id,d.question_count,d.seconds_per_question) into q;
  update duels set rematch_code = q->>'code' where id=p_duel;
  return q;
end $$;

-- 8. New duels only pick questions that HAVE a correct answer configured (voided ones are skipped)
create or replace function create_duel(p_paper_id uuid, p_question_count int default 10, p_seconds int default 45)
returns jsonb language plpgsql security definer set search_path=public as $$
declare qids uuid[]; did uuid; c text; n int;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if exists(select 1 from profiles where id=auth.uid() and is_suspended) then raise exception 'Your account is suspended'; end if;
  if p_question_count not between 5 and 20 then raise exception 'Question count must be 5–20'; end if;
  if p_seconds not between 15 and 120 then raise exception 'Time per question must be 15–120 seconds'; end if;
  select count(*) into n from questions where paper_id=p_paper_id and cardinality(_duel_keys(id)) > 0;
  if n < 1 then raise exception 'This paper has no questions with a correct answer set'; end if;
  p_question_count := least(p_question_count,n);
  select array_agg(id order by random()) into qids from (
    select id from questions where paper_id=p_paper_id and cardinality(_duel_keys(id)) > 0 order by random() limit p_question_count) s;
  c := _duel_code();
  insert into duels(code,paper_id,host_id,question_ids,question_count,seconds_per_question)
  values(c,p_paper_id,auth.uid(),qids,p_question_count,p_seconds)
  returning id into did;
  return jsonb_build_object('duel_id',did,'code',c);
end $$;

-- ===== v4 =====
-- A/L Master — duel v4: missed-answer records, per-question review, duel history.
-- Run AFTER migration-duels-v3.sql. Safe to re-run.

-- Remove older versions first (a different return type can't be replaced in place).
drop function if exists advance_duel(uuid);
drop function if exists get_duel_review(uuid);
drop function if exists get_duel_history(int);
drop function if exists get_duel_reveal(uuid);
drop function if exists _duel_rescore(uuid);

-- 1. A missed question now gets a real duel_answers row (selected = null, is_correct = false)
alter table duel_answers alter column selected drop not null;

-- 2. advance_duel: on time-out, lock unlocked picks, then write "missed" rows for anyone with nothing
create or replace function advance_duel(p_duel uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; idx int; hmiss int; gmiss int; full_ms int; qid uuid;
begin
  select * into d from duels where id=p_duel for update;
  if d.id is null or (d.host_id<>auth.uid() and d.guest_id<>auth.uid()) then raise exception 'Not a player'; end if;

  if d.status='countdown' and now()>=d.phase_deadline then
    update duels set status='question', current_index=0, question_started_at=now(),
      phase_deadline=now()+make_interval(secs=>seconds_per_question),
      host_answered=false, guest_answered=false, host_choice=null, guest_choice=null where id=p_duel;

  elsif d.status='question' and now()>=d.phase_deadline then
    full_ms := d.seconds_per_question*1000;
    qid := d.question_ids[d.current_index+1];
    if not d.host_answered and d.host_choice is not null then perform _duel_record(p_duel, d.host_id, d.host_choice, full_ms); end if;
    if not d.guest_answered and d.guest_choice is not null and d.guest_id is not null then perform _duel_record(p_duel, d.guest_id, d.guest_choice, full_ms); end if;
    select * into d from duels where id=p_duel;

    if not d.host_answered then
      insert into duel_answers(duel_id,question_id,user_id,selected,is_correct,ms_taken)
      values(p_duel,qid,d.host_id,null,false,full_ms) on conflict (duel_id,question_id,user_id) do nothing;
    end if;
    if not d.guest_answered and d.guest_id is not null then
      insert into duel_answers(duel_id,question_id,user_id,selected,is_correct,ms_taken)
      values(p_duel,qid,d.guest_id,null,false,full_ms) on conflict (duel_id,question_id,user_id) do nothing;
    end if;

    hmiss := case when d.host_answered then 0 else d.host_missed_streak+1 end;
    gmiss := case when d.guest_answered then 0 else d.guest_missed_streak+1 end;
    if hmiss>=3 or gmiss>=3 then
      update duels set status='finished', finished_at=now(), host_missed_streak=hmiss, guest_missed_streak=gmiss where id=p_duel;
    else
      update duels set status='discuss', phase_deadline=now()+make_interval(secs=>d.discuss_seconds),
        discuss_extended=false, host_ready=false, guest_ready=false,
        host_missed_streak=hmiss, guest_missed_streak=gmiss where id=p_duel;
    end if;

  elsif d.status='discuss' and (now()>=d.phase_deadline or (d.host_ready and d.guest_ready)) then
    perform _duel_rescore(p_duel);
    idx := d.current_index+1;
    if idx>=d.question_count then
      update duels set status='finished', finished_at=now() where id=p_duel;
    else
      update duels set status='question', current_index=idx, question_started_at=now(),
        phase_deadline=now()+make_interval(secs=>seconds_per_question),
        host_answered=false, guest_answered=false, host_choice=null, guest_choice=null,
        discuss_extended=false, host_ready=false, guest_ready=false where id=p_duel;
    end if;
  end if;
  return get_duel_state(p_duel);
end $$;

-- 3. Review of every question that was played (only once the duel is over)
create or replace function get_duel_review(p_duel uuid)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare d duels; myid uuid := auth.uid(); out jsonb;
begin
  select * into d from duels where id=p_duel and (host_id=myid or guest_id=myid);
  if not found then raise exception 'Duel not found'; end if;
  if d.status not in ('finished','abandoned') then raise exception 'Review opens when the duel ends'; end if;
  select coalesce(jsonb_agg(item order by (item->>'index')::int), '[]'::jsonb) into out from (
    select jsonb_build_object(
      'index', t.ord-1,
      'number', q.question_number,
      'image', q.question_image_url,
      'correct', to_jsonb(_duel_keys(q.id)),
      'review', coalesce(q.review_text,''),
      'review_image', q.review_image_url,
      'host',  (select jsonb_build_object('choice',a.selected::text,'correct',coalesce(a.selected is not null and a.selected::text = any(_duel_keys(q.id)),false)) from duel_answers a where a.duel_id=d.id and a.question_id=q.id and a.user_id=d.host_id limit 1),
      'guest', (select jsonb_build_object('choice',a.selected::text,'correct',coalesce(a.selected is not null and a.selected::text = any(_duel_keys(q.id)),false)) from duel_answers a where a.duel_id=d.id and a.question_id=q.id and a.user_id=d.guest_id limit 1)
    ) as item
    from unnest(d.question_ids) with ordinality as t(qid, ord)
    join questions q on q.id=t.qid
    where t.ord-1 <= d.current_index
  ) s;
  return out;
end $$;

-- 4. Duel history for the dashboard and the history page
create or replace function get_duel_history(p_limit int default 50)
returns table (
  duel_id uuid, code text, status text, paper_title text, paper_subject text, paper_year int,
  question_count int, my_score int, their_score int, opponent_name text, opponent_avatar text,
  created_at timestamptz, finished_at timestamptz
) language sql security definer stable set search_path=public as $$
  select d.id, d.code, d.status::text, p.title, p.subject, p.year, d.question_count,
         case when d.host_id=auth.uid() then d.host_score else d.guest_score end,
         case when d.host_id=auth.uid() then d.guest_score else d.host_score end,
         coalesce(o.display_name, o.full_name, case when o.id is null then null else 'Player' end),
         o.avatar_url, d.created_at, d.finished_at
  from duels d
  join papers p on p.id=d.paper_id
  left join profiles o on o.id = case when d.host_id=auth.uid() then d.guest_id else d.host_id end
  where (d.host_id=auth.uid() or d.guest_id=auth.uid())
    and not (d.status='lobby' and d.created_at < now()-interval '30 minutes')
  order by d.created_at desc
  limit least(greatest(p_limit,1),200)
$$;

-- 5. Scores are recomputed from the answers against the CURRENT answer key.
--    (If a question's key is fixed in the admin panel after players answered, points now follow it.)
create or replace function _duel_rescore(p_duel uuid)
returns void language plpgsql security definer set search_path=public as $$
declare d duels; hs int; gs int;
begin
  select * into d from duels where id=p_duel;
  if not found then return; end if;
  update duel_answers a
     set is_correct = (a.selected is not null and a.selected::text = any(_duel_keys(q.id)))
    from questions q
   where a.duel_id=p_duel and q.id=a.question_id
     and a.is_correct is distinct from (a.selected is not null and a.selected::text = any(_duel_keys(q.id)));
  select coalesce(sum(case when a.is_correct then 10 + least(5,greatest(0,
           floor((d.seconds_per_question*1000-a.ms_taken)::numeric/(d.seconds_per_question*200))::int)) else 0 end),0)::int
    into hs from duel_answers a where a.duel_id=p_duel and a.user_id=d.host_id;
  select coalesce(sum(case when a.is_correct then 10 + least(5,greatest(0,
           floor((d.seconds_per_question*1000-a.ms_taken)::numeric/(d.seconds_per_question*200))::int)) else 0 end),0)::int
    into gs from duel_answers a where a.duel_id=p_duel and a.user_id=d.guest_id;
  if hs is distinct from d.host_score or gs is distinct from d.guest_score then
    update duels set host_score=hs, guest_score=gs where id=p_duel;
  end if;
end $$;
revoke all on function _duel_rescore(uuid) from public, anon, authenticated;

-- 6. Reveal: rescore first, so what players see always matches the current key
create or replace function get_duel_reveal(p_duel uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels; qid uuid; q questions; ha duel_answers; ga duel_answers; myid uuid := auth.uid();
begin
  select * into d from duels where id=p_duel and (host_id=myid or guest_id=myid);
  if not found then raise exception 'Duel not found'; end if;
  if d.status not in ('discuss','finished') then raise exception 'Reveal is not ready'; end if;
  perform _duel_rescore(p_duel);
  qid := d.question_ids[d.current_index+1];
  select * into q from questions where id=qid;
  if not found then raise exception 'Question not found'; end if;
  select * into ha from duel_answers where duel_id=d.id and question_id=qid and user_id=d.host_id limit 1;
  select * into ga from duel_answers where duel_id=d.id and question_id=qid and user_id=d.guest_id limit 1;
  return jsonb_build_object(
    'question_id', qid,
    'correct', to_jsonb(_duel_keys(qid)),
    'review', coalesce(q.review_text,''),
    'review_image', q.review_image_url,
    'host', case when ha.id is null then jsonb_build_object('choice',null,'correct',false,'ms',null)
                 else jsonb_build_object('choice',ha.selected::text,'correct',coalesce(ha.is_correct,false),'ms',ha.ms_taken) end,
    'guest', case when ga.id is null then jsonb_build_object('choice',null,'correct',false,'ms',null)
                  else jsonb_build_object('choice',ga.selected::text,'correct',coalesce(ga.is_correct,false),'ms',ga.ms_taken) end);
end $$;
