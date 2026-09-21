import { mountThemeToggle } from "./shell.js";

const NAV = [
  ["index.html", "Overview"],
  ["papers.html", "Papers"],
  ["users.html", "Students"],
  ["ads.html", "Advertising"],
];

export function mountAdminShell(title, actionHtml = "") {
  const path = location.pathname.split("/").pop();
  document.getElementById("admin-header").innerHTML = `
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
  document.getElementById("admin-title").textContent = title;
}
