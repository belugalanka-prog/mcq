import { supabase } from "./supabase.js";
import { dbError } from "./db.js";

/** Returns { user, profile } or null. Never throws. */
function saveReturnUrl() {
  const path = `${location.pathname.split("/").pop() || "index.html"}${location.search}${location.hash}`;
  if (!/^[A-Za-z0-9_./-]+\.html(?:\?[^#]*)?(?:#.*)?$/.test(path)) return;
  try { sessionStorage.setItem("auth_return_url", path); sessionStorage.setItem("auth_return_at", String(Date.now())); } catch (_) {}
}

function consumeReturnUrl() {
  try {
    const at = Number(sessionStorage.getItem("auth_return_at") || 0);
    const target = sessionStorage.getItem("auth_return_url") || "";
    if (!at || Date.now() - at > 15 * 60 * 1000) {
      sessionStorage.removeItem("auth_return_url"); sessionStorage.removeItem("auth_return_at"); return "";
    }
    sessionStorage.removeItem("auth_return_url"); sessionStorage.removeItem("auth_return_at");
    if (/^[A-Za-z0-9_./-]+\.html(?:\?[^#]*)?(?:#.*)?$/.test(target)) return target;
  } catch (_) {}
  return "";
}

export async function getSession() {
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  dbError(userError, "checking sign-in", { silent: true });
  if (!user) return null;
  const returnUrl = location.pathname.endsWith("/dashboard.html") ? consumeReturnUrl() : "";
  if (returnUrl && !location.pathname.endsWith(returnUrl.split("?")[0])) {
    location.replace(returnUrl);
    return null;
  }
  const { data: profile, error: profileError } = await supabase.from("profiles").select("*").eq("id", user.id).single();
  dbError(profileError, "loading your profile");
  return { user, profile };
}

/** Redirects to / if not signed in. Call at the top of every protected page. */
export async function requireUser() {
  const session = await getSession();
  if (!session) {
    saveReturnUrl();
    location.href = "index.html?signin=1";
    return null;
  }
  return session;
}

/** Redirects to dashboard.html if not admin/teacher. */
export async function requireStaff() {
  const session = await requireUser();
  if (!session) return null;
  if (!["admin", "teacher"].includes(session.profile?.role)) {
    location.href = "dashboard.html";
    return null;
  }
  return session;
}

export async function signInWithGoogle() {
  const base = (window.APP_CONFIG.SITE_URL || location.origin).replace(/\/+$/, "");
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${base}/dashboard.html` },
  });
  dbError(error, "signing in");
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  dbError(error, "signing out", { silent: true });
  location.href = "index.html";
}
