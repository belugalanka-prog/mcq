import { supabase } from "./supabase.js";
import { dbError } from "./db.js";
import { signOut } from "./auth.js";
import { esc } from "./format.js";

const ICONS = {
  grid: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg>',
  book: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H19v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 1 6.5 18H19v3H6.5"/></svg>',
  clock: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  chart: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20V10"/><path d="M10 20V4"/><path d="M16 20v-7"/><path d="M22 20H2"/></svg>',
  trophy: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 4h8v5a4 4 0 0 1-8 0z"/><path d="M8 5H5v2a3 3 0 0 0 3 3"/><path d="M16 5h3v2a3 3 0 0 1-3 3"/><path d="M10 13v3h4v-3"/><path d="M8 20h8"/><path d="M12 16v4"/></svg>',
  user: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-3.5 3.6-6 8-6s8 2.5 8 6"/></svg>',
  sun: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/></svg>',
  moon: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5"/></svg>',
  search: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
  menu: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  close: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  layers: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="m12 3 9 5-9 5-9-5z"/><path d="m3 13 9 5 9-5"/></svg>',
  zap: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg>',
  file: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h6"/></svg>',
  logout: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/></svg>',
  back: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>',
};

/**
 * Goes back to wherever the visitor actually came from, but never off the
 * site entirely: if the browser's referrer isn't this app (a bookmark, a
 * shared link, a new tab), history.back() would land them somewhere
 * outside the app, so we send them to `fallback` instead.
 */
export function goBack(fallback) {
  try {
    if (document.referrer && new URL(document.referrer).origin === location.origin && history.length > 1) {
      history.back();
      return;
    }
  } catch {}
  location.href = fallback;
}

const NAV = [
  ["dashboard.html", "Dashboard", "grid"],
  ["subject.html", "Papers", "book"],
  ["results-index.html", "My results", "clock"],
  ["leaderboard.html", "Leaderboard", "trophy"],
  ["profile.html", "Profile", "user"],
];

function navHtml(cls) {
  const path = location.pathname.split("/").pop();
  return NAV.map(([href, label, icon]) => {
    const active = href.split("?")[0] === path;
    return `<a href="${href}" class="${cls} ${active ? "active" : ""}" title="${label}" aria-label="${label}">${ICONS[icon]}</a>`;
  }).join("");
}

/** Desktop side rail. Phones get the labelled menu in the top bar instead (see mountTopbar). */
export function mountRail() {
  if (document.querySelector(".rail")) return;
  const rail = document.createElement("nav");
  rail.className = "rail";
  rail.setAttribute("aria-label", "Main");
  rail.innerHTML = navHtml("rail-item");
  document.body.appendChild(rail);
}

// Everything reachable from the phone menu — one place, labelled, no icon-only guessing.
const MENU_MAIN = [
  ["dashboard.html", "Dashboard", "grid"],
  ["subject.html", "Papers", "book"],
  ["topics.html", "Practice by lesson", "layers"],
  ["results-index.html", "My results", "clock"],
  ["leaderboard.html", "Leaderboard", "trophy"],
  ["duel-history.html", "Duels", "zap"],
  ["profile.html", "Profile", "user"],
];
const MENU_LEGAL = [
  ["privacy.html", "Privacy Policy", "file"],
  ["terms.html", "Terms & Conditions", "file"],
];

function brandLink(home, extra = "") {
  return `<a href="${home}" class="brand-link ${extra}" aria-label="A/L Master — home"><span class="sf-mark"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></span><span class="brand-name display">A/L Master</span></a>`;
}

function mountMobileMenu(btn, home) {
  const path = location.pathname.split("/").pop() || "index.html";
  const item = ([href, label, icon]) =>
    `<a class="mm-link" href="${href}"${href === path ? ' aria-current="page"' : ""}>${ICONS[icon]}<span>${label}</span></a>`;

  const host = document.createElement("div");
  host.innerHTML = `
    <div class="mm-backdrop" data-mm-close></div>
    <aside class="mm" id="mobile-menu" role="dialog" aria-modal="true" aria-label="Site menu">
      <div class="mm-head">
        ${brandLink(home)}
        <button type="button" class="mm-close" data-mm-close aria-label="Close menu">${ICONS.close}</button>
      </div>
      ${MENU_MAIN.map(item).join("")}
      <div class="mm-sep"></div>
      ${MENU_LEGAL.map(item).join("")}
      <div class="mm-sep"></div>
      <p class="mm-label">Theme</p>
      <div class="theme-toggle">
        <button type="button" data-theme-btn="light">${ICONS.sun} Light</button>
        <button type="button" data-theme-btn="dark">${ICONS.moon} Dark</button>
      </div>
      <button type="button" class="mm-link hidden" id="mm-signout" style="margin-top:8px">${ICONS.logout}<span>Sign out</span></button>
    </aside>`;
  while (host.firstChild) document.body.appendChild(host.firstChild);

  const root = document.documentElement;
  const menu = document.getElementById("mobile-menu");
  const closeBtn = menu.querySelector(".mm-close");
  const focusable = () => [...menu.querySelectorAll("a[href],button:not(.hidden)")];

  const setOpen = (open) => {
    root.classList.toggle("mm-open", open);
    btn.setAttribute("aria-expanded", String(open));
    if (open) closeBtn.focus(); else btn.focus({ preventScroll: true });
  };
  btn.addEventListener("click", () => setOpen(!root.classList.contains("mm-open")));
  document.querySelectorAll("[data-mm-close]").forEach((el) => el.addEventListener("click", () => setOpen(false)));
  menu.querySelectorAll("a.mm-link").forEach((a) => a.addEventListener("click", () => root.classList.remove("mm-open")));
  document.addEventListener("keydown", (e) => {
    if (!root.classList.contains("mm-open")) return;
    if (e.key === "Escape") { setOpen(false); return; }
    if (e.key === "Tab") {                       // keep focus inside the open menu
      const f = focusable(); if (!f.length) return;
      const first = f[0], last = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  });
  // If the window is widened past the phone breakpoint, drop the open state.
  matchMedia("(min-width:768px)").addEventListener?.("change", (m) => { if (m.matches) root.classList.remove("mm-open"); });

  // Only offer "Sign out" when someone is actually signed in (the legal pages are public).
  supabase.auth.getSession().then(({ data }) => {
    if (!data?.session) return;
    const out = document.getElementById("mm-signout");
    out?.classList.remove("hidden");
    out?.addEventListener("click", signOut);
  }).catch(() => {});
}

/**
 * Renders the top bar into #topbar. tabs: [{href,label}], action?: {href,label}
 * back: false hides the back button (used on the dashboard, which is home);
 * otherwise it goes to whatever page the visitor actually came from, or to
 * backFallback (default dashboard.html) if that isn't part of this app.
 */
export function mountTopbar({ tabs, action, search = true, back = true, backFallback = "dashboard.html", home = "dashboard.html" }) {
  const el = document.getElementById("topbar");
  if (!el) return;

  // Lets keyboard users jump past the navigation.
  const main = document.querySelector(".wrap");
  if (main && !document.querySelector(".skip-link")) {
    main.id = main.id || "main";
    const skip = document.createElement("a");
    skip.className = "skip-link"; skip.href = `#${main.id}`; skip.textContent = "Skip to content";
    document.body.prepend(skip);
  }

  el.className = "topbar";
  el.innerHTML = `
    ${back ? `<button type="button" id="topbar-back" class="back-btn" aria-label="Back" title="Back">${ICONS.back}</button>` : ""}
    ${brandLink(home)}
    <nav class="row tabs" style="gap:4px" aria-label="Page sections">
      ${tabs.map((t, i) => `<a href="${t.href}" class="pill ${i === 0 ? "pill-soft" : "pill-ghost"}"${i === 0 ? ' aria-current="page"' : ""}>${t.label}</a>`).join("")}
    </nav>
    ${search ? `<div class="search">${ICONS.search}<input id="topbar-search" type="search" aria-label="Search papers, topics or years" placeholder="Search papers, topics or years"></div>` : ""}
    <div class="row topbar-tools" style="margin-left:auto">
      <div class="theme-toggle" id="theme-toggle">
        <button type="button" data-theme-btn="light">${ICONS.sun} Light</button>
        <button type="button" data-theme-btn="dark">${ICONS.moon} Dark</button>
      </div>
      ${action ? `<a href="${action.href}" class="pill pill-deep">${action.label}</a>` : ""}
    </div>
    <button type="button" class="menu-btn" id="menu-btn" aria-label="Open menu" aria-expanded="false" aria-controls="mobile-menu">${ICONS.menu}</button>
  `;
  mountMobileMenu(document.getElementById("menu-btn"), home);
  mountThemeToggle();
  if (search) mountSearch();
  if (back) document.getElementById("topbar-back")?.addEventListener("click", () => goBack(backFallback));
}

/**
 * Wires up the top-bar search input.
 *
 * Any page can opt in to live client-side filtering by tagging each
 * filterable element with `data-search-item="<searchable text>"` and,
 * optionally, one element with `data-search-empty` to show when a query
 * matches nothing. If a page has no such items (e.g. the dashboard),
 * pressing Enter falls back to jumping to the Papers page with the query.
 */
export function mountSearch() {
  const input = document.getElementById("topbar-search");
  if (!input) return;

  const params = new URLSearchParams(location.search);
  const initial = params.get("q") || "";
  if (initial) input.value = initial;

  const items = () => [...document.querySelectorAll("[data-search-item]")];

  const applyFilter = (raw) => {
    const query = raw.trim().toLowerCase();
    const list = items();
    if (!list.length) return;
    let visible = 0;
    list.forEach((el) => {
      const text = (el.dataset.searchItem || el.textContent || "").toLowerCase();
      const match = !query || text.includes(query);
      el.style.display = match ? "" : "none";
      if (match) visible++;
    });
    document.querySelectorAll("[data-search-empty]").forEach((el) => {
      el.style.display = query && visible === 0 ? "" : "none";
    });
  };

  input.addEventListener("input", () => applyFilter(input.value));

  input.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    const q = input.value.trim();
    if (!q) return;
    if (items().length) { e.preventDefault(); return; }
    location.href = `subject.html?q=${encodeURIComponent(q)}`;
  });

  if (initial) applyFilter(initial);
}

export function mountThemeToggle() {
  const root = document.documentElement;
  let stored = "light";
  try { stored = localStorage.getItem("theme") || "light"; } catch {}
  root.dataset.theme = stored;

  document.querySelectorAll("[data-theme-btn]").forEach((btn) => {
    if (btn.dataset.bound) return;               // safe to call more than once
    btn.dataset.bound = "1";
    btn.classList.toggle("active", btn.dataset.themeBtn === stored);
    btn.setAttribute("aria-pressed", String(btn.dataset.themeBtn === stored));
    btn.addEventListener("click", () => {
      root.dataset.theme = btn.dataset.themeBtn;
      try { localStorage.setItem("theme", btn.dataset.themeBtn); } catch {}
      document.querySelectorAll("[data-theme-btn]").forEach((b) => {
        b.classList.toggle("active", b.dataset.themeBtn === btn.dataset.themeBtn);
        b.setAttribute("aria-pressed", String(b.dataset.themeBtn === btn.dataset.themeBtn));
      });
    });
  });
}

/** Appends the site footer (brand, link columns, legal, contact) to the end of `el` (defaults to .wrap). */
export function mountFooter(el = document.querySelector(".wrap")) {
  if (!el || el.querySelector(".site-footer")) return;
  const cfg = window.APP_CONFIG || {};
  const email = (cfg.CONTACT_EMAIL || "").trim();
  const phone = (cfg.CONTACT_PHONE || "").trim();
  const tel = phone.replace(/[^\d+]/g, "");
  const footer = document.createElement("footer");
  footer.className = "site-footer";
  footer.innerHTML = `
    <div class="sf-brand">
      ${brandLink("index.html")}
    </div>
    <p class="muted sf-about">Timed A/L Physics and Chemistry MCQ papers for Sri Lankan students — past, topic and model papers with an instant topic breakdown.</p>
    <div class="sf-cols">
      <div><p class="sf-h">Subjects</p>
        <a href="subject.html?subject=physics">Physics</a>
        <a href="subject.html?subject=chemistry">Chemistry</a></div>
      <div><p class="sf-h">Explore</p>
        <a href="subject.html">All papers</a>
        <a href="topics.html">Lessons</a>
        <a href="leaderboard.html">Leaderboard</a>
        <a href="duel-history.html">Duels</a>
        <a href="dashboard.html">Dashboard</a></div>
      <div><p class="sf-h">Your account</p>
        <a href="profile.html">Profile</a>
        <a href="results-index.html">My results</a></div>
      <div><p class="sf-h">Legal &amp; contact</p>
        <a href="privacy.html">Privacy Policy</a>
        <a href="terms.html">Terms &amp; Conditions</a>
        <button type="button" class="sf-btn" data-cookie-settings>Cookie settings</button>
        ${email ? `<a class="sf-contact" href="mailto:${esc(email)}">${esc(email)}</a>` : ""}
        ${tel ? `<a class="sf-contact" href="tel:${esc(tel)}">${esc(phone)}</a>` : ""}</div>
    </div>
    <div class="sf-base">
      <span class="muted">© ${new Date().getFullYear()} A/L Master. All rights reserved.</span>
      <span class="muted">Practise smarter. Score higher.</span>
    </div>`;
  el.appendChild(footer);
  footer.querySelector("[data-cookie-settings]")?.addEventListener("click", () => window.Consent?.open());
}

/** Applies the stored theme before paint, to avoid a flash. Call in <head>. */
export function applyStoredTheme() {
  try {
    document.documentElement.dataset.theme = localStorage.getItem("theme") || "light";
  } catch {}
}

/**
 * Renders one ad into `el`. House ads (sold directly) win over AdSense.
 * Nothing is ever called on the exam page — see exam.html, which does not
 * import this at all.
 */
export async function mountAdSlot(el, placement, minHeight = 220) {
  if (!el) return;
  const today = new Date().toISOString().slice(0, 10);

  // Fetch every active row for this placement and pick the date window in
  // JS. (Two chained .or() calls used to do this server-side, but Postgrest
  // doesn't reliably combine two same-named `or=` filters — the row could
  // get excluded even when it should match, so ads silently never showed.
  // Filtering client-side sidesteps that entirely and is just as cheap for
  // a table this small.)
  const { data: candidates, error: adError } = await supabase
    .from("advertisements")
    .select("id, title, image_url, link_url, start_date, end_date")
    .eq("placement", placement)
    .eq("is_active", true)
    .order("priority", { ascending: false });

  if (dbError(adError, `loading ${placement} ad`, { silent: true })) { el.remove(); return; }

  const ad = (candidates ?? []).find(a =>
    (!a.start_date || a.start_date <= today) && (!a.end_date || a.end_date >= today));

  // Only http(s) links and https images are ever rendered or opened, whatever is in the table.
  const safeUrl = (u, httpsOnly) => { try { const x = new URL(u); return (x.protocol === "https:" || (!httpsOnly && x.protocol === "http:")) ? x.href : null; } catch { return null; } };
  const adImg = ad && safeUrl(ad.image_url, true);
  const adLink = ad && safeUrl(ad.link_url, false);

  if (ad && adImg) {
    el.className = "card";
    el.style.overflow = "hidden";
    el.style.cursor = "pointer";
    el.style.minHeight = `${minHeight}px`;
    el.innerHTML = `<img src="${adImg}" alt="Advertisement" loading="lazy" decoding="async" style="width:100%;height:100%;min-height:${minHeight}px;object-fit:cover;display:block">`;
    el.onclick = () => {
      supabase.rpc("track_ad_event", { p_ad_id: ad.id, p_type: "click", p_placement: placement });
      if (adLink) window.open(adLink, "_blank", "noopener,noreferrer");
    };

    const io = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) {
        supabase.rpc("track_ad_event", { p_ad_id: ad.id, p_type: "impression", p_placement: placement });
        io.disconnect();
      }
    }, { threshold: 0.5 });
    io.observe(el);
    return;
  }

  // Fall back to AdSense, if a slot is configured for this placement.
  const settingKey = {
    DASHBOARD_PROMO: "adsense_slot_dashboard",
    PAPER_TOP: "adsense_slot_paper_top",
    RESULT_BOTTOM: "adsense_slot_result",
    SIDEBAR: "adsense_slot_sidebar",
  }[placement];

  const client = window.APP_CONFIG.ADSENSE_CLIENT;
  // Google ads set cookies, so they only load once the visitor has said yes in the cookie banner.
  if (!client || !settingKey || !window.Consent?.allowsAds()) { el.remove(); return; }

  const { data: rows, error: settingsError } = await supabase
    .from("app_settings").select("key,value").in("key", ["adsense_enabled", settingKey]);
  if (dbError(settingsError, "loading ad settings", { silent: true })) { el.remove(); return; }
  const enabled = rows?.find((r) => r.key === "adsense_enabled")?.value !== false;
  const slot = rows?.find((r) => r.key === settingKey)?.value;

  if (!enabled || !slot) { el.remove(); return; }

  el.className = "card";
  el.style.padding = "12px";
  el.innerHTML = `
    <p style="font-size:11px;color:var(--muted);margin-bottom:8px">Advertisement</p>
    <ins class="adsbygoogle" style="display:block;min-height:${minHeight}px"
         data-ad-client="${client}" data-ad-slot="${slot}"
         data-ad-format="auto" data-full-width-responsive="true"></ins>`;

  (window.adsbygoogle = window.adsbygoogle || []).push({});
}
