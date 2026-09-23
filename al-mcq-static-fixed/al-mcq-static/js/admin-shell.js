import { mountThemeToggle, goBack } from "./shell.js";

const ICON_BACK = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>';

const NAV = [
  ["index.html", "Overview"],
  ["papers.html", "Papers"],
  ["users.html", "Students"],
  ["reports.html", "Reports"],
  ["requests.html", "Requests"],
  ["announcements.html", "Announcements"],
  ["ads.html", "Advertising"],
];

export function mountAdminShell(title, actionHtml = "") {
  const path = location.pathname.split("/").pop();
  const isHome = path === "index.html" || path === "";
  document.getElementById("admin-header").innerHTML = `
    ${isHome ? "" : `<button type="button" id="admin-back" class="back-btn" aria-label="Back" title="Back">${ICON_BACK}</button>`}
    <p class="display" style="font-size:16px;margin-right:8px">Admin</p>
    <nav class="row">
      ${NAV.map(([href,label]) => `<a href="${href}" class="pill ${href===path?"pill-soft":"pill-ghost"}">${label}</a>`).join("")}
    </nav>
    <div class="row" style="margin-left:auto">
      <div class="theme-toggle" id="theme-toggle">
        <button data-theme-btn="light">Light</button>
        <button data-theme-btn="dark">Dark</button>
      </div>
      <a href="../../dashboard.html" class="pill pill-ghost">Student view</a>
      ${actionHtml}
    </div>`;
  mountThemeToggle();
  if (!isHome) document.getElementById("admin-back")?.addEventListener("click", () => goBack("index.html"));
  document.getElementById("admin-title").textContent = title;
}
