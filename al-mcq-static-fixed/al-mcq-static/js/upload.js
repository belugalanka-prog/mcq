import { supabase } from "./supabase.js";

export const IMG_RE = /\.(png|jpe?g|webp|gif|bmp|avif)$/i;

/** 001.png -> 1, "q12.jpg" -> 12, "12 final.png" -> 12, "Screenshot (7).png" -> 7 (last number in the name) */
export function numberFromName(name) {
  const m = name.match(/(\d+)\D*\.[a-z0-9]+$/i);
  if (!m) return null;
  const n = parseInt(m[1], 10);
  return Number.isFinite(n) && n > 0 ? n : null;
}

export async function toWebp(file) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return new Promise((res, rej) => canvas.toBlob(b => b ? res(b) : rej(new Error("Could not convert image")), "image/webp", 0.82));
}

/** Run worker(item, index) over items with at most `limit` running at once. */
export async function pool(items, limit, worker) {
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) { const idx = i++; await worker(items[idx], idx); }
  }));
}

/** items: [{file, n}]. Returns { rows, failed } — rows are ready for saveQuestionRows. */
export async function uploadQuestionImages(paper, items, onProgress = () => {}) {
  const rows = [], failed = [];
  let done = 0;
  await pool(items, 4, async ({ file, n }) => {
    try {
      const webp = await toWebp(file);
      const path = `${paper.subject}/${paper.year ?? "misc"}/${paper.id}/q${String(n).padStart(3, "0")}.webp`;
      const { error } = await supabase.storage.from("questions").upload(path, webp, { contentType: "image/webp", upsert: true });
      if (error) throw error;
      const { data } = supabase.storage.from("questions").getPublicUrl(path);
      rows.push({ question_number: n, question_image_url: data.publicUrl });
    } catch (e) {
      failed.push(`${file.name}: ${e.message ?? "failed"}`);
    }
    onProgress(++done, items.length);
  });
  return { rows, failed };
}

/** New questions get answer "A"; existing ones only get their image replaced, so re-uploading never wipes an answer key. */
export async function saveQuestionRows(paper, rows) {
  const { data: existing, error: existingError } = await supabase.from("questions").select("question_number").eq("paper_id", paper.id);
  if (existingError) throw existingError;
  const have = new Set((existing ?? []).map(q => q.question_number));
  const fresh = rows.filter(r => !have.has(r.question_number)).map(r => ({ ...r, paper_id: paper.id, correct_answer: "A" }));
  const old = rows.filter(r => have.has(r.question_number));
  if (fresh.length) {
    const { error } = await supabase.from("questions").insert(fresh);
    if (error) throw error;
  }
  const updateFailed = [];
  await pool(old, 5, async r => {
    const { error } = await supabase.from("questions").update({ question_image_url: r.question_image_url })
      .eq("paper_id", paper.id).eq("question_number", r.question_number);
    if (error) updateFailed.push(r.question_number);
  });
  if (updateFailed.length) throw new Error(`Saved, but ${updateFailed.length} image replacement(s) failed to save (question ${updateFailed.join(", ")}).`);
  return { added: fresh.length, replaced: old.length };
}
