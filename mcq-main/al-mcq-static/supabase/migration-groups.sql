-- Run once in Supabase → SQL Editor. Adds "group" (sir / series name) to papers.
alter table papers add column if not exists group_name text;
create index if not exists papers_group_idx on papers (subject, paper_type, group_name);
