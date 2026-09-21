import { supabase } from "./supabase.js";

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
};

const NAV = [
  ["dashboard.html", "Dashboard", "grid"],
  ["subject.html?subject=physics", "Papers", "book"],
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

/** Call once per page: injects the rail and returns nothing. */
export function mountRail() {
  const rail = document.createElement("nav");
  rail.className = "rail";
  rail.innerHTML = navHtml("rail-item");
  document.body.appendChild(rail);

  const mobile = document.createElement("nav");
  mobile.className = "rail-mobile";
  mobile.innerHTML = navHtml("rail-item");
  document.body.appendChild(mobile);
}

/** Renders the top bar into #topbar. tabs: [{href,label}], action?: {href,label} */
export function mountTopbar({ tabs, action, search = true }) {
  const el = document.getElementById("topbar");
  if (!el) return;

  el.className = "topbar";
  el.innerHTML = `
    <nav class="row" style="gap:4px">
      ${tabs.map((t, i) => `<a href="${t.href}" class="pill ${i === 0 ? "pill-soft" : "pill-ghost"}">${t.label}</a>`).join("")}
    </nav>
    ${search ? `<div class="search">${ICONS.search}<input placeholder="Search papers, topics or years"></div>` : ""}
    <div class="row" style="margin-left:auto">
      <div class="theme-toggle" id="theme-toggle">
        <button data-theme-btn="light">${ICONS.sun} Light</button>
        <button data-theme-btn="dark">${ICONS.moon} Dark</button>
      </div>
      ${action ? `<a href="${action.href}" class="pill pill-deep">${action.label}</a>` : ""}
    </div>
  `;
  mountThemeToggle();
}

export function mountThemeToggle() {
  const root = document.documentElement;
  const stored = localStorage.getItem("theme") || "light";
  root.dataset.theme = stored;

  document.querySelectorAll("[data-theme-btn]").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.themeBtn === stored);
    btn.addEventListener("click", () => {
      root.dataset.theme = btn.dataset.themeBtn;
      localStorage.setItem("theme", btn.dataset.themeBtn);
      document.querySelectorAll("[data-theme-btn]").forEach((b) =>
        b.classList.toggle("active", b === btn)
      );
    });
  });
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

  const { data: ad } = await supabase
    .from("advertisements")
    .select("id, title, image_url, link_url")
    .eq("placement", placement)
    .eq("is_active", true)
    .or(`start_date.is.null,start_date.lte.${today}`)
    .or(`end_date.is.null,end_date.gte.${today}`)
    .order("priority", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (ad) {
    el.className = "card";
    el.style.overflow = "hidden";
    el.style.cursor = "pointer";
    el.innerHTML = `<img src="${ad.image_url}" alt="${ad.title ?? "Advertisement"}" style="width:100%;height:100%;object-fit:cover;display:block">`;
    el.onclick = () => {
      supabase.rpc("track_ad_event", { p_ad_id: ad.id, p_type: "click", p_placement: placement });
      window.open(ad.link_url ?? "#", "_blank", "noopener");
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
  if (!client || !settingKey) { el.remove(); return; }

  const { data: rows } = await supabase
    .from("app_settings").select("key,value").in("key", ["adsense_enabled", settingKey]);
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
