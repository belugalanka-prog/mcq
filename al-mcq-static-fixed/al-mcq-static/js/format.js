export const CHOICES = ["A", "B", "C", "D", "E"];

export function clock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  const m = Math.floor(s / 60);
  return `${String(m).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

export function titleCase(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}

export function esc(s) {
  const d = document.createElement("div");
  d.textContent = s ?? "";
  return d.innerHTML;
}

export function qs(name, fallback = null) {
  return new URLSearchParams(location.search).get(name) ?? fallback;
}
