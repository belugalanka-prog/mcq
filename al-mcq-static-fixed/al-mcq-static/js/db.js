// Shared helper so a failed Supabase call never fails silently.
//
// Usage:
//   const { data: papers, error } = await supabase.from("papers").select("*");
//   if (dbError(error, "loading papers")) return;
//
// `dbError` returns true when there was an error (so callers can `return`
// or `continue` in one line), logs the real error to the console for
// debugging, and shows a toast so the user isn't just staring at a blank
// or zero state with no idea anything went wrong.
export function dbError(error, context, { silent = false } = {}) {
  if (!error) return false;
  console.error(context ? `[${context}]` : "[supabase]", error);
  if (!silent) {
    const detail = error.message || error.error_description || error.hint || "Please try again.";
    toast(`${context ? context + ": " : ""}${detail}`, "error");
  }
  return true;
}

let toastHost = null;

export function toast(message, type = "info") {
  if (!toastHost) {
    toastHost = document.createElement("div");
    toastHost.id = "app-toast-host";
    toastHost.style.cssText =
      "position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:9999;" +
      "display:flex;flex-direction:column;gap:8px;align-items:center;pointer-events:none";
    document.body.appendChild(toastHost);
  }
  const item = document.createElement("div");
  item.textContent = message;
  item.style.cssText =
    "pointer-events:auto;padding:10px 16px;border-radius:10px;font-size:13px;" +
    "font-family:inherit;line-height:1.4;color:#fff;box-shadow:0 4px 16px rgba(0,0,0,.25);" +
    "max-width:340px;text-align:center;opacity:0;transform:translateY(6px);" +
    "transition:opacity .18s ease,transform .18s ease;" +
    `background:${type === "error" ? "#dc2626" : type === "success" ? "#16a34a" : "#111827"}`;
  toastHost.appendChild(item);
  requestAnimationFrame(() => {
    item.style.opacity = "1";
    item.style.transform = "translateY(0)";
  });
  setTimeout(() => {
    item.style.opacity = "0";
    item.style.transform = "translateY(6px)";
    setTimeout(() => item.remove(), 200);
  }, type === "error" ? 5000 : 3000);
}
