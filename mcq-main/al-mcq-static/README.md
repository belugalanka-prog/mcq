# A/L Master — static edition (no Node, no npm, no build step)

Plain HTML, CSS and JavaScript. Supabase and AdSense are loaded from `<script>` tags at the
top of each page — there is nothing here for Vercel to build.

```
Your computer                 GitHub → Vercel
❌ No Node.js needed           serves these files as-is
❌ No npm install
❌ No build command
```

When Vercel imports this repo it will show **Framework Preset: Other** and there will be no
`npm install` / `npm run build` step in the deploy log at all — just files being copied to the
edge.

---

## Deploy in about fifteen minutes

### 1. Create the Supabase project

[supabase.com](https://supabase.com) → New project. Pick a region near Sri Lanka (Singapore is
closest).

### 2. Run the schema

Supabase → **SQL Editor** → **New query** → paste the whole of `supabase/schema.sql` → **Run**.

This single file replaces everything the old Next.js server used to do: it creates every table,
the RLS policies, and — because there is no server left to run them — five Postgres functions that
stand in for what used to be API routes:

| Used to be | Now is |
|---|---|
| `POST /api/attempts` | `supabase.rpc("start_attempt", …)` |
| `PATCH /api/attempts/:id/answers` | `supabase.rpc("save_answer", …)` |
| `POST /api/attempts/:id/submit` | `supabase.rpc("submit_attempt", …)` |
| `POST /api/attempts/:id/reveal` | `supabase.rpc("reveal_answer", …)` |
| `/auth/callback` creating a profile | a trigger on `auth.users` (`handle_new_user`) |
| the service-role column filter on `questions` | `get_exam_questions()`, which is the only thing allowed to return question rows to a student, and only four columns |

All five are `SECURITY DEFINER`, meaning they run with elevated rights for that one specific,
narrow job — the same shape of trust a server route used to hold, just written in SQL instead of
TypeScript. The browser only ever calls them with the public anon key.

### 3. Create the storage buckets

Supabase → **Storage** → New bucket, three times, all **Public**: `questions`, `reviews`, `ads`.

### 4. Google sign-in

1. [Google Cloud Console](https://console.cloud.google.com) → Credentials → Create credentials →
   OAuth client ID → **Web application**.
2. Authorised redirect URI: `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`.
3. Paste the client ID and secret into Supabase → Authentication → Providers → Google.
4. Supabase → Authentication → URL Configuration:
   - Site URL: `https://your-site.vercel.app`
   - Redirect URLs: add `https://your-site.vercel.app/dashboard.html` and
     `https://*.vercel.app/dashboard.html` for preview deploys.

Unlike the Next.js build there is no `/auth/callback` route — `signInWithGoogle()` in `js/auth.js`
sends Google straight back to `dashboard.html`, and `supabase-js` reads the session out of the URL
itself (`detectSessionInUrl: true`).

### 5. Fill in `config.js`

```js
window.APP_CONFIG = {
  SUPABASE_URL: "https://YOUR-PROJECT-REF.supabase.co",
  SUPABASE_ANON_KEY: "your-anon-key",   // safe to expose — RLS is what actually protects data
  ADSENSE_CLIENT: "",                   // fill in once AdSense approves you
  SITE_URL: "https://your-site.vercel.app",
};
```

The anon key is meant to be public. Every table it can touch is locked down by the RLS policies in
`schema.sql`, and the one column that must stay secret — `questions.correct_answer` before
submission — is withheld by `get_exam_questions()` rather than by hiding the key.

### 6. Push and deploy

```bash
git init && git add -A && git commit -m "A/L MCQ platform — static edition"
gh repo create al-mcq-static --private --source=. --push
```

On [vercel.com](https://vercel.com): **Add New → Project → Import**. Vercel will detect no
framework and no build command — that's expected. Deploy. No environment variables are needed on
Vercel's side at all, since `config.js` carries everything and it's a plain public file.

### 7. Make yourself an admin

Sign in once with Google on the live site, then in Supabase SQL Editor:

```sql
update profiles set role = 'admin' where full_name = 'Your Name';
```

`/pages/admin/index.html` is now open to you. A student who types that URL directly still gets
served the HTML — the middleware.ts route guard from the Next.js build doesn't exist in a static
site — but every table it reads is protected by `is_staff()` in RLS, so the page loads and shows
nothing. If you want the URL itself to bounce non-admins, that's the one piece of behaviour this
edition trades away for having no server.

### Working on it locally

Any static file server works, e.g.:

```bash
python3 -m http.server 8000
```

Then open `http://localhost:8000`. There's no watch step, no rebuild — edit an `.html` file and
reload the tab.

---

## Google AdSense (serving ads)

1. Apply at [adsense.google.com](https://adsense.google.com) with your domain. Buy a real domain
   first and attach it in Vercel → Settings → Domains — reviewers commonly reject `*.vercel.app`
   subdomains, and approval needs a few complete, published papers plus privacy and contact pages
   already live.
2. Once approved, put your publisher ID in `config.js` as `ADSENSE_CLIENT`.
3. Edit `ads.txt` and replace the placeholder publisher ID with yours — without a matching
   `ads.txt`, most buyers won't bid on your inventory, which quietly caps what you earn.
4. In AdSense, create a display ad unit per placement and copy its slot ID into `app_settings`:

```sql
update app_settings set value = to_jsonb('1234567890'::text) where key = 'adsense_slot_dashboard';
update app_settings set value = to_jsonb('2345678901'::text) where key = 'adsense_slot_paper_top';
update app_settings set value = to_jsonb('3456789012'::text) where key = 'adsense_slot_result';
update app_settings set value = to_jsonb('4567890123'::text) where key = 'adsense_slot_sidebar';
```

Slots live in the database, not in code, so you can move or switch off a placement by running SQL
— no redeploy. `adsense_enabled = false` turns all of it off at once.

**No revenue dashboard in this edition.** Reading real earnings needs the AdSense Management API,
which authenticates with an OAuth client *secret* — that cannot go in a static page's JavaScript
without anyone who views source being able to read your Google account's token. Check actual
earnings at adsense.google.com, or ask me for the small serverless-function version if you want the
numbers inside `/admin` again (it's one Vercel function, everything else here stays exactly as is).

**Two ad systems share the same slot.** An ad you sold directly (`/pages/admin/ads.html`) always
wins over AdSense at that placement, because a fixed rate you negotiated beats an auction. Its
impressions and clicks are counted by this app itself, through `track_ad_event()`, and shown right
there in the admin ads page — that part needed no server either.

**Nothing renders on `exam.html`.** That file never imports the ad-slot code at all. Interrupting a
timed paper costs more in abandoned attempts than the impression is worth, and accidental clicks on
a screen students are tapping through quickly are exactly the pattern that gets AdSense accounts
flagged. Never click your own ads, and never ask students to — it's the most common reason accounts
get terminated, and termination is usually permanent.

---

## How answers stay secret without a server

- `questions` has no student-facing RLS policy at all.
- The only way to read question rows before submission is `get_exam_questions()`, and it returns
  exactly four columns — `id, question_number, question_image_url, topic`. `correct_answer` is not
  among them.
- Marking happens inside `submit_attempt()`. The browser sends only which letter a student picked;
  the comparison against `correct_answer` happens inside Postgres.
- The exam timer is read from `attempts.expires_at` on every tick. Changing the system clock or
  editing the countdown in devtools buys nothing, because grading checks the same server-side
  deadline again on submit.

## What's built

Everything from the Next.js version except the pieces that specifically needed a server:

| Area | State |
|---|---|
| Google sign-in, auto-created profile via trigger | Done |
| Subject browsing, exam runner, resume, practice mode | Done |
| Server-side-equivalent marking (Postgres functions) | Done |
| Topic breakdown, wrong-answer review | Done |
| Leaderboards, streaks, points | Done |
| Admin: papers, bulk upload, answer key, publish guard | Done |
| Admin: students, student detail, hardest questions | Done |
| AdSense serving + directly-sold ads with click/impression tracking | Done |
| AdSense revenue dashboard | Not in this edition — needs a tiny server for the token exchange |
| Weekly/monthly leaderboard reset | Call `select reset_period_points('weekly')` from Supabase's
  pg_cron extension (Database → Cron) on a Monday-at-midnight schedule, since there is no Vercel
  Cron in a static site |
