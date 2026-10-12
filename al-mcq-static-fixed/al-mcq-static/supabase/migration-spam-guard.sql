-- =====================================================================
-- Spam guard (OPTIONAL, safe to re-run).  Run in Supabase → SQL Editor.
--
-- The forms in the browser have a honeypot + cooldown, but anyone can call the
-- Supabase API directly, so the real limit has to live in the database.
--   * paper_requests : max 5 per user per hour, note 8–500 chars
--   * question_reports: max 20 per user per hour, reason 1–500 chars
-- Staff (is_staff()) are exempt.
-- =====================================================================

create or replace function guard_paper_requests() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if is_staff() then return new; end if;
  if char_length(trim(new.note)) < 8 or char_length(new.note) > 500 then
    raise exception 'Please describe the paper in 8 to 500 characters.';
  end if;
  if (select count(*) from paper_requests
        where user_id = new.user_id and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'You have sent several requests recently. Please try again later.';
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_paper_requests on paper_requests;
create trigger trg_guard_paper_requests before insert on paper_requests
  for each row execute function guard_paper_requests();

create or replace function guard_question_reports() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if is_staff() then return new; end if;
  if char_length(trim(new.reason)) < 1 or char_length(new.reason) > 500 then
    raise exception 'Please describe the problem in up to 500 characters.';
  end if;
  if (select count(*) from question_reports
        where user_id = new.user_id and created_at > now() - interval '1 hour') >= 20 then
    raise exception 'You have sent many reports recently. Please try again later.';
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_question_reports on question_reports;
create trigger trg_guard_question_reports before insert on question_reports
  for each row execute function guard_question_reports();
