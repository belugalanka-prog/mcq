# SEO guide — A/L Master

## Why Google wasn't showing the site (in order of impact)
1. **Only 3 pages are indexable** (home, privacy, terms). Every other page is login-only and correctly `noindex`. Google can only rank what it can read without signing in, so the home page now carries real content (done).
2. **`almcq.vercel.app` is a shared subdomain** with no authority. A custom domain is the single biggest remaining fix.
3. **Search Console is not verified and the sitemap is not submitted** (steps below — needs your Google account).
4. A new site can take days to weeks to be crawled. Requesting indexing speeds it up.
5. `sw.js` and `js/sw.js` import a third-party ad/push script from `3nbf4.com`. Nothing registers them, so they are inert, but delete both files unless you deliberately use that network — ad/push scripts can get a site flagged by Safe Browsing and hurt trust.

## Verify Search Console (5 minutes)
1. search.google.com/search-console → Add property.
2. Best: **Domain** property on a custom domain (DNS TXT record). For `almcq.vercel.app` choose **URL prefix** → HTML tag, copy the `<meta name="google-site-verification" content="...">` line, paste it inside `<head>` of `index.html`, deploy, click Verify.
3. Sitemaps → submit `sitemap.xml`.
4. URL Inspection → paste `https://almcq.vercel.app/` → **Request indexing**. Repeat for `/privacy.html` and `/terms.html`.
5. If you move to a custom domain: update `SITE_URL` in `config.js`, every canonical/og URL, `sitemap.xml`, `robots.txt`, the Supabase Site URL and redirect URLs, and 308-redirect the old domain.

## Backlink strategy (realistic for a student MCQ site)
**Free, do first**
- Link from your own profiles: GitHub, LinkedIn, Facebook page, YouTube channel descriptions, Telegram/WhatsApp study groups (mostly nofollow, but they drive crawls and users).
- Submit to Product Hunt, AlternativeTo and Sri Lankan startup / EdTech lists.
- Sri Lankan A/L communities (Facebook groups, r/srilanka, forums): answer questions and link only where genuinely relevant. No spam.

**Earned (highest value)**
- Teachers and tuition classes: offer free access or a custom paper; ask for a link from their class page or video descriptions.
- School Physics/Chemistry/ICT societies and university clubs (.ac.lk / .edu links carry weight).
- Guest posts and roundups such as "Best A/L Physics revision resources".

**Content that earns links (build next)**
- Public, static topic pages (e.g. "A/L Physics — Mechanics MCQ guide") each with a sample question. Today nothing exists beyond the home page for others to link to.
- An exam-season updates page (timetable, paper-pattern changes).

**Avoid**: bought links, link farms, comment spam, PBNs.
**Track**: Search Console → Links, monthly. Target 5–10 relevant referring domains in the first 3 months.
