import { supabase } from "./supabase.js";

// Live site totals (active students / active papers) with a count-up animation.
// Expects a container with two elements: [data-k="users"] and [data-k="papers"].
// Data comes from the get_site_stats() database function and is refreshed every 10s while the tab is visible.

const CSS = `
.stats{display:flex;justify-content:center;margin-top:44px;opacity:0;transform:translateY(6px);transition:opacity .5s ease,transform .5s ease}
.stats.on{opacity:1;transform:none}
.stat{padding:0 38px;text-align:center}
.stat+.stat{border-left:1px solid var(--hairline)}
.stat-num{display:block;font:600 clamp(28px,4.4vw,38px)/1.1 Poppins,sans-serif;letter-spacing:-.02em;font-variant-numeric:tabular-nums;color:var(--ink)}
.stat span{display:block;margin-top:6px;font-size:13.5px;color:var(--muted)}
.stats-left{justify-content:flex-start;margin-top:22px;padding-top:18px;border-top:1px solid var(--hairline)}
.stats-left .stat{padding:0 28px 0 0;text-align:left}
.stats-left .stat+.stat{padding-left:28px}
.stats-left .stat-num{font-size:clamp(24px,3.2vw,30px)}
@media(max-width:520px){.stat{padding:0 22px}.stats-left .stat{padding:0 20px 0 0}.stats-left .stat+.stat{padding-left:20px}}
`;

export function mountSiteStats(box) {
  if (!box) return;
  if (!document.getElementById("site-stats-css")) {
    const st = document.createElement("style");
    st.id = "site-stats-css";
    st.textContent = CSS;
    document.head.appendChild(st);
  }

  const targets = { users: box.querySelector('[data-k="users"]'), papers: box.querySelector('[data-k="papers"]') };
  const shown = { users: 0, papers: 0 };
  const frames = {};
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const fmt = (n) => Math.round(n).toLocaleString("en-US");

  function countTo(key, to, ms) {
    const el = targets[key], from = shown[key];
    cancelAnimationFrame(frames[key]);
    shown[key] = to;
    if (reduce || from === to) { el.textContent = fmt(to); return; }
    const t0 = performance.now();
    const step = (now) => {
      const p = Math.min(1, (now - t0) / ms);
      el.textContent = fmt(from + (to - from) * (1 - Math.pow(1 - p, 3)));
      if (p < 1) frames[key] = requestAnimationFrame(step);
    };
    frames[key] = requestAnimationFrame(step);
  }

  // Hold the first count-up until the intro curtain has gone.
  const introGone = () => new Promise((res) => {
    const t0 = Date.now();
    const tick = () => (!document.getElementById("intro") || Date.now() - t0 > 5000) ? res() : setTimeout(tick, 120);
    tick();
  });

  let first = true;
  async function load() {
    const { data, error } = await supabase.rpc("get_site_stats");
    if (error || !data) { if (first) box.remove(); return; }
    if (first) { await introGone(); box.classList.add("on"); }
    const ms = first ? 1600 : 900;
    first = false;
    countTo("users", Number(data.users) || 0, ms);
    countTo("papers", Number(data.papers) || 0, ms);
  }

  load();
  setInterval(() => { if (!document.hidden && !first) load(); }, 10000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden && !first) load(); });
}
