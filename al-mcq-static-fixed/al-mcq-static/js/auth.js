import { supabase } from "./supabase.js";

/** Returns { user, profile } or null. Never throws. */
export async function getSession() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data: profile } = await supabase.from("profiles").select("*").eq("id", user.id).single();
  return { user, profile };
}

/** Redirects to / if not signed in. Call at the top of every protected page. */
export async function requireUser() {
  const session = await getSession();
  if (!session) {
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
  const base = window.APP_CONFIG.SITE_URL || location.origin + location.pathname.replace(/[^/]*$/, "");
  await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${base}dashboard.html` },
  });
}

export async function signOut() {
  await supabase.auth.signOut();
  location.href = "index.html";
}
