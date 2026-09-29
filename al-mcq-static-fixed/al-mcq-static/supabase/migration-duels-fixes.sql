-- A/L Master — duel fixes. Safe to run on top of migration-duels.sql (all CREATE OR REPLACE).

-- 1. Code generator: gen_random_bytes lives in the "extensions" schema on Supabase and was
--    not visible from create_duel (search_path=public), so creating a duel could fail.
create or replace function _duel_code()
returns text language plpgsql volatile set search_path=public as $$
declare c text;
begin
  loop
    c := upper(substr(md5(random()::text || clock_timestamp()::text),1,6));
    exit when not exists(select 1 from duels where code=c);
  end loop;
  return c;
end $$;

-- 2. Rejoining: a guest who refreshed the page mid-duel got "already started".
create or replace function join_duel(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d duels;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if exists(select 1 from profiles where id=auth.uid() and is_suspended) then raise exception 'Your account is suspended'; end if;
  select * into d from duels where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Duel not found'; end if;
  if d.host_id=auth.uid() or d.guest_id=auth.uid() then return jsonb_build_object('duel_id',d.id,'code',d.code); end if;
  if d.guest_id is not null then raise exception 'This duel already has two players'; end if;
  if d.status<>'lobby' then raise exception 'This duel has already started'; end if;
  if d.created_at < now()-interval '30 minutes' then raise exception 'This duel code has expired'; end if;
  update duels set guest_id=auth.uid() where id=d.id;
  return jsonb_build_object('duel_id',d.id,'code',d.code);
end $$;

-- 3. Answers: null-safe correct answer, idempotent insert, streak reset when a player answers.
create or replace function submit_duel_answer(p_duel uuid, p_question uuid, p_choice answer_choice)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d duels; idx int; ms int; correct boolean; pts int;
  uid uuid := auth.uid(); ishost boolean; q_correct answer_choice;
begin
  if uid is null then raise exception 'Sign in required'; end if;
  if p_choice is null then raise exception 'Please select an answer'; end if;

  select * into d from duels where id=p_duel for update;
  if not found then raise exception 'Duel not found'; end if;
  if d.host_id is distinct from uid and d.guest_id is distinct from uid then raise exception 'Not a player in this duel'; end if;
  if d.status<>'question' then raise exception 'Answers are locked'; end if;

  idx := d.current_index+1;
  if d.question_ids[idx] is distinct from p_question then raise exception 'Wrong question'; end if;
  if now() > d.phase_deadline + interval '1 second' then raise exception 'Time is up'; end if;

  ishost := d.host_id=uid;
  if (ishost and d.host_answered) or ((not ishost) and d.guest_answered) then
    return jsonb_build_object('already',true);
  end if;

  select correct_answer into q_correct from questions where id=p_question;
  if q_correct is null then raise exception 'This question has no correct answer configured'; end if;
  correct := (q_correct = p_choice);

  ms := greatest(0, least((extract(epoch from (now()-d.question_started_at))*1000)::int, d.seconds_per_question*1000+1000));
  pts := case when correct then 10 + least(5, greatest(0, floor((d.seconds_per_question*1000-ms)::numeric/(d.seconds_per_question*200))::int)) else 0 end;

  insert into duel_answers(duel_id,question_id,user_id,selected,is_correct,ms_taken)
  values(p_duel,p_question,uid,p_choice,correct,ms)
  on conflict (duel_id,question_id,user_id) do nothing;

  if ishost then
    update duels set host_answered=true, host_score=host_score+pts, host_missed_streak=0 where id=p_duel;
  else
    update duels set guest_answered=true, guest_score=guest_score+pts, guest_missed_streak=0 where id=p_duel;
  end if;

  select * into d from duels where id=p_duel;
  if d.host_answered and d.guest_answered then
    update duels set status='discuss', phase_deadline=now()+make_interval(secs=>d.discuss_seconds),
      discuss_extended=false, host_ready=false, guest_ready=false where id=p_duel;
  end if;
  return jsonb_build_object('correct',correct,'points',pts,'ms_taken',ms);
end $$;

-- 4. "Ready": when both players are ready, move on immediately (before, nothing advanced until the timer ran out).
create or replace function duel_ready(p_duel uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare d duels;
begin
  select * into d from duels where id=p_duel for update;
  if d.id is null or (d.host_id is distinct from auth.uid() and d.guest_id is distinct from auth.uid()) then raise exception 'Not a player'; end if;
  if d.status<>'discuss' then return false; end if;
  if d.host_id=auth.uid() then update duels set host_ready=true where id=p_duel;
  else update duels set guest_ready=true where id=p_duel; end if;
  select * into d from duels where id=p_duel;
  if d.host_ready and d.guest_ready then perform advance_duel(p_duel); end if;
  return true;
end $$;

-- 5. Reveal (your version): always returns host/guest objects, never null.
create or replace function get_duel_reveal(p_duel uuid)
returns jsonb language plpgsql security definer stable set search_path=public as $$
declare d duels; qid uuid; q questions; ha duel_answers; ga duel_answers; myid uuid := auth.uid();
begin
  select * into d from duels where id=p_duel and (host_id=myid or guest_id=myid);
  if not found then raise exception 'Duel not found'; end if;
  if d.status not in ('discuss','finished') then raise exception 'Reveal is not ready'; end if;
  qid := d.question_ids[d.current_index+1];
  select * into q from questions where id=qid;
  if not found then raise exception 'Question not found'; end if;
  select * into ha from duel_answers where duel_id=d.id and question_id=qid and user_id=d.host_id limit 1;
  select * into ga from duel_answers where duel_id=d.id and question_id=qid and user_id=d.guest_id limit 1;
  return jsonb_build_object(
    'question_id', qid,
    'correct', q.correct_answer::text,
    'review', coalesce(q.review_text,''),
    'review_image', q.review_image_url,
    'host', case when ha.id is null then jsonb_build_object('choice',null,'correct',false,'ms',null)
                 else jsonb_build_object('choice',ha.selected::text,'correct',coalesce(ha.is_correct,false),'ms',ha.ms_taken) end,
    'guest', case when ga.id is null then jsonb_build_object('choice',null,'correct',false,'ms',null)
                  else jsonb_build_object('choice',ga.selected::text,'correct',coalesce(ga.is_correct,false),'ms',ga.ms_taken) end);
end $$;
