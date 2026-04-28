/**
 * Research Hub data layer — tag-driven, no sectors/types.
 *
 * Talks to the post-redesign Supabase schema:
 *   reports(id, title, description, tags TEXT[], featured, pinned, size,
 *           file_url, starred, created_at, author_id)
 *   tags(name, description, pinned, ...)
 *   tag_stats VIEW (name, pinned, description, count, last_updated)
 *   related_tags(p_tag, p_limit) RPC
 */
import { supabase } from "@/integrations/supabase/client";

export type CardSize = "xl" | "l" | "wide" | "m" | "s";
export type TagGroup = "pinned" | "tickers" | "themes" | "custom";

export interface Report {
  id: string;
  title: string;
  description: string | null;
  tags: string[];
  featured: boolean;
  pinned: boolean;
  size: CardSize | null;        // explicit override; null → derive
  file_url: string | null;
  starred: boolean;
  created_at: string;           // ISO
  author_id: string | null;
}

export interface Tag {
  name: string;
  description: string | null;
  pinned: boolean;
  count: number;
  last_updated: string | null;  // ISO
  group: TagGroup;
}

// ─── DB row types ─────────────────────────────────────────────
interface DbReport {
  id: string;
  title: string;
  description: string | null;
  tags: string[] | null;
  featured: boolean;
  pinned: boolean;
  size: string | null;
  file_url: string | null;
  starred: boolean;
  created_at: string;
  author_id: string | null;
}

interface DbTagStat {
  name: string;
  description: string | null;
  pinned: boolean;
  count: number;
  last_updated: string | null;
}

// ─── Group classification ─────────────────────────────────────
const TICKER_RE = /^[A-Z][A-Z0-9.\-]{0,5}$/;
function classifyGroup(name: string, pinned: boolean): TagGroup {
  if (pinned) return "pinned";
  if (TICKER_RE.test(name)) return "tickers";
  // multi-word lowercase = theme; single-word lowercase = custom
  if (/[a-z]/.test(name) && /\s/.test(name.trim())) return "themes";
  if (/^[a-z]/.test(name)) return "themes";
  return "custom";
}

// ─── Card-size derivation ─────────────────────────────────────
const DAY_MS = 86_400_000;
export function deriveSize(r: Report): CardSize {
  if (r.size) return r.size;
  if (r.featured) return "xl";
  const days = (Date.now() - new Date(r.created_at).getTime()) / DAY_MS;
  if (r.pinned && days <= 7) return "l";
  if (days <= 7 && r.description) return "m";
  if (days <= 30) return "s";
  return "s";
}

// ─── Date formatting ──────────────────────────────────────────
export function formatDate(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  return d.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

// ─── Mappers ──────────────────────────────────────────────────
function dbToReport(r: DbReport): Report {
  const validSizes: CardSize[] = ["xl", "l", "wide", "m", "s"];
  const size =
    r.size && validSizes.includes(r.size as CardSize)
      ? (r.size as CardSize)
      : null;
  return {
    id: r.id,
    title: r.title,
    description: r.description,
    tags: r.tags ?? [],
    featured: r.featured,
    pinned: r.pinned,
    size,
    file_url: r.file_url,
    starred: r.starred,
    created_at: r.created_at,
    author_id: r.author_id,
  };
}

function dbToTag(t: DbTagStat): Tag {
  return {
    name: t.name,
    description: t.description,
    pinned: t.pinned,
    count: t.count,
    last_updated: t.last_updated,
    group: classifyGroup(t.name, t.pinned),
  };
}

// ─── Queries ──────────────────────────────────────────────────

export async function fetchReports(): Promise<Report[]> {
  const { data, error } = await supabase
    .from("reports" as never)
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return ((data ?? []) as unknown as DbReport[]).map(dbToReport);
}

export async function fetchReportById(id: string): Promise<Report | null> {
  const { data, error } = await supabase
    .from("reports" as never)
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data ? dbToReport(data as unknown as DbReport) : null;
}

export async function fetchTags(): Promise<Tag[]> {
  // Read from the tag_stats view (joins reports for counts).
  const { data, error } = await supabase
    .from("tag_stats" as never)
    .select("*")
    .order("count", { ascending: false });
  if (error) throw error;
  return ((data ?? []) as unknown as DbTagStat[]).map(dbToTag);
}

export async function fetchRelatedTags(
  tag: string,
  limit = 8,
): Promise<{ name: string; count: number }[]> {
  const { data, error } = await (supabase.rpc as unknown as (
    name: string,
    args: { p_tag: string; p_limit: number },
  ) => Promise<{ data: { name: string; count: number }[] | null; error: unknown }>)(
    "related_tags",
    { p_tag: tag, p_limit: limit },
  );
  if (error) throw error;
  return data ?? [];
}

export interface NewReport {
  title: string;
  description: string;
  tags: string[];
  featured: boolean;
  pinned: boolean;
  file?: File;
}

export async function createReport(input: NewReport): Promise<Report> {
  // Upload file first if present. Wrapped in a timeout so a stalled
  // storage request fails loudly instead of leaving the UI stuck on
  // "Publishing…" forever.
  let file_url: string | null = null;
  if (input.file) {
    const ext = input.file.name.split(".").pop()?.toLowerCase() ?? "bin";
    const path = `${crypto.randomUUID()}.${ext}`;

    const uploadPromise = supabase.storage
      .from("reports")
      .upload(path, input.file, {
        contentType: input.file.type || "application/octet-stream",
        upsert: false,
      });

    const timeout = new Promise<never>((_, reject) =>
      setTimeout(
        () =>
          reject(
            new Error(
              "Storage upload timed out after 30s. The bucket may be misconfigured, or the file is too large.",
            ),
          ),
        30_000,
      ),
    );

    const result = (await Promise.race([uploadPromise, timeout])) as Awaited<
      typeof uploadPromise
    >;
    if (result.error) {
      throw new Error(`Storage upload failed: ${result.error.message}`);
    }
    file_url = path;
  }

  const { data: authData } = await supabase.auth.getUser();
  const author_id = authData.user?.id ?? null;

  const { data, error } = await supabase
    .from("reports" as never)
    .insert({
      title: input.title.trim(),
      description: input.description.trim() || null,
      tags: input.tags.map((t) => t.replace(/^#/, "").trim()).filter(Boolean),
      featured: input.featured,
      pinned: input.pinned,
      file_url,
      author_id,
    } as never)
    .select()
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    // RLS lets the insert through but blocks the SELECT-after-insert. Most
    // likely the signed-in user's email is not in the `members` allowlist.
    throw new Error(
      "Insert blocked by RLS — your email is not in the members allowlist.",
    );
  }
  return dbToReport(data as unknown as DbReport);
}

export async function setTagPinned(
  name: string,
  pinned: boolean,
): Promise<void> {
  const { error } = await supabase
    .from("tags" as never)
    .upsert({ name, pinned } as never)
    .eq("name", name);
  if (error) throw error;
}

export async function setTagDescription(
  name: string,
  description: string | null,
): Promise<void> {
  const { error } = await supabase
    .from("tags" as never)
    .upsert({ name, description } as never)
    .eq("name", name);
  if (error) throw error;
}

export async function deleteReport(
  id: string,
  file_url: string | null,
): Promise<void> {
  if (file_url) {
    const { error: rmErr } = await supabase.storage
      .from("reports")
      .remove([file_url]);
    if (rmErr && !/not.?found/i.test(rmErr.message)) throw rmErr;
  }
  const { error } = await supabase
    .from("reports" as never)
    .delete()
    .eq("id", id);
  if (error) throw error;
}

export async function fetchReportHtml(file_url: string | null): Promise<string> {
  if (!file_url) throw new Error("No file attached to this report");
  const { data, error } = await supabase.storage
    .from("reports")
    .download(file_url);
  if (error || !data) throw error ?? new Error("Download failed");
  return data.text();
}
