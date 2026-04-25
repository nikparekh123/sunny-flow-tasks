export type ReportType = "single" | "macro" | "theme" | "earn";
export type SectorKey = "tech" | "energy" | "fin" | "hlth" | "macro" | "indu" | "stpl";
export type FreshState = "new" | "unread" | "read";
export type Visibility = "Team" | "Firm-wide" | "Private";

export interface Report {
  d: string;
  tickers: string[];
  typ: ReportType;
  sec: SectorKey;
  sectors: string[];
  title: string;
  author: string;
  read: string;
  star: boolean;
  fresh: FreshState;
  tags: string[];
  summary: string;
  visibility: Visibility;
}

export type ViewKey = "latest" | "sector" | "author" | "type" | "starred";

export const typeLabel: Record<ReportType, string> = {
  single: "Single",
  macro: "Macro",
  theme: "Theme",
  earn: "Earnings",
};

export const secLabel: Record<SectorKey, string> = {
  tech: "Technology",
  energy: "Energy",
  fin: "Financials",
  hlth: "Healthcare",
  macro: "Macro",
  indu: "Industrials",
  stpl: "Staples",
};

// Seed data removed — the app now starts with an empty `reports` table and
// grows only through real uploads.

export const SECTORS: { k: SectorKey | "all"; label: string; count: number }[] = [
  { k: "all",    label: "All",         count: 168 },
  { k: "tech",   label: "Technology",  count: 42 },
  { k: "energy", label: "Energy",      count: 31 },
  { k: "fin",    label: "Financials",  count: 38 },
  { k: "hlth",   label: "Healthcare",  count: 22 },
  { k: "macro",  label: "Macro",       count: 19 },
  { k: "indu",   label: "Industrials", count: 9 },
  { k: "stpl",   label: "Staples",     count: 7 },
];

export const TYPES: { k: ReportType | "all"; label: string; count: number }[] = [
  { k: "all",    label: "All",          count: 168 },
  { k: "single", label: "Single-stock", count: 84 },
  { k: "macro",  label: "Macro",        count: 41 },
  { k: "theme",  label: "Thematic",     count: 23 },
  { k: "earn",   label: "Earnings",     count: 20 },
];

export const RECENCY = [
  { k: "1d",  label: "Today",      count: 6 },
  { k: "7d",  label: "This week",  count: 24 },
  { k: "30d", label: "This month", count: 71 },
  { k: "90d", label: "This qtr",   count: 168 },
];

export const VIEWS: { k: ViewKey; label: string; count: number | null }[] = [
  { k: "latest",  label: "Latest",    count: 168 },
  { k: "sector",  label: "By sector", count: null },
  { k: "author",  label: "By author", count: null },
  { k: "type",    label: "By type",   count: null },
  { k: "starred", label: "Starred",   count: 12 },
];

export interface Group<T extends Report = Report> {
  key: string;
  title: string | null;
  items: T[];
}

export function groupRows<T extends Report>(rows: T[], view: ViewKey): Group<T>[] {
  if (view === "latest") return [{ key: "_", title: null, items: rows }];
  if (view === "starred") return [{ key: "starred", title: null, items: rows.filter((r) => r.star) }];
  if (view === "sector") {
    const order: SectorKey[] = ["tech", "energy", "fin", "macro", "hlth"];
    return order
      .map((k) => ({ key: k, title: secLabel[k] || k, items: rows.filter((r) => r.sec === k) }))
      .filter((g) => g.items.length);
  }
  if (view === "author") {
    const authors = [...new Set(rows.map((r) => r.author))].sort();
    return authors.map((a) => ({ key: a, title: a, items: rows.filter((r) => r.author === a) }));
  }
  if (view === "type") {
    const order: ReportType[] = ["single", "macro", "theme", "earn"];
    return order
      .map((k) => ({ key: k, title: typeLabel[k], items: rows.filter((r) => r.typ === k) }))
      .filter((g) => g.items.length);
  }
  return [{ key: "_", title: null, items: rows }];
}

// ---------- Supabase mapping ----------
import { supabase } from "@/integrations/supabase/client";

type DbReport = {
  id: string;
  title: string;
  tickers: string[] | null;
  report_type: string;
  primary_sector: string | null;
  sectors: string[] | null;
  author: string | null;
  published_at: string | null;
  read_minutes: number | null;
  tags: string[] | null;
  summary: string | null;
  visibility: string;
  file_path: string | null;
  starred: boolean;
  created_at: string;
};

const sectorKeyFromLabel = (s?: string | null): SectorKey => {
  const v = (s || "").toLowerCase();
  if (v.startsWith("tech")) return "tech";
  if (v.startsWith("energ")) return "energy";
  if (v.startsWith("financ") || v === "fin") return "fin";
  if (v.startsWith("health") || v === "hlth") return "hlth";
  if (v.startsWith("macro")) return "macro";
  if (v.startsWith("indu")) return "indu";
  if (v.startsWith("stap") || v === "stpl") return "stpl";
  return "tech";
};

const formatShortDate = (iso: string | null): string => {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  return d.toLocaleString("en-US", { month: "short", day: "numeric" });
};

export interface ReportRow extends Report {
  id: string;
  file_path: string | null;
}

export function dbToReport(r: DbReport): ReportRow {
  const typ = (["single", "macro", "theme", "earn"].includes(r.report_type) ? r.report_type : "single") as ReportType;
  const sec = sectorKeyFromLabel(r.primary_sector);
  return {
    id: r.id,
    d: formatShortDate(r.published_at || r.created_at),
    tickers: r.tickers || [],
    typ,
    sec,
    sectors: r.sectors && r.sectors.length ? r.sectors : [secLabel[sec]],
    title: r.title,
    author: r.author || "—",
    read: (r.read_minutes ?? 10) + "m",
    star: !!r.starred,
    fresh: "read",
    tags: r.tags || [],
    summary: r.summary || "",
    visibility: (["Team", "Firm-wide", "Private"].includes(r.visibility) ? r.visibility : "Team") as Visibility,
    file_path: r.file_path,
  };
}

export function getReportPublicUrl(file_path: string | null): string | null {
  if (!file_path) return null;
  const { data } = supabase.storage.from("reports").getPublicUrl(file_path);
  return data.publicUrl ?? null;
}

// Supabase Storage forces HTML files to be served as text/plain for XSS
// protection — so opening the public URL renders the source, not the page.
// Workaround: download the bytes, wrap them in a client-side Blob with
// text/html, and open that blob URL. The browser renders it normally.
export async function deleteReport(id: string, file_path: string | null): Promise<void> {
  if (file_path) {
    const { error: rmErr } = await supabase.storage.from("reports").remove([file_path]);
    // If the file is already gone, press on — we still want to remove the row.
    if (rmErr && !/not.?found/i.test(rmErr.message)) throw rmErr;
  }
  const { error } = await supabase.from("reports").delete().eq("id", id);
  if (error) throw error;
}

// Supabase Storage forces HTML files to be served as text/plain for XSS
// protection, so `<iframe src=publicUrl>` would show the source, not the
// page. We download the bytes and return them so the caller can feed
// `srcDoc` on an iframe — that always renders as HTML.
export async function fetchReportHtml(file_path: string | null): Promise<string> {
  if (!file_path) throw new Error("No file attached to this report");
  const { data, error } = await supabase.storage.from("reports").download(file_path);
  if (error || !data) throw error ?? new Error("Download failed");
  return data.text();
}

export async function fetchReportById(id: string): Promise<ReportRow | null> {
  const { data, error } = await supabase.from("reports").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  return data ? dbToReport(data as DbReport) : null;
}

export async function setReportStar(id: string, starred: boolean): Promise<void> {
  const { error } = await supabase.from("reports").update({ starred }).eq("id", id);
  if (error) throw error;
}

export async function fetchReports(): Promise<ReportRow[]> {
  const { data, error } = await supabase
    .from("reports")
    .select("*")
    .order("published_at", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as DbReport[]).map(dbToReport);
}

// Sample-data auto-seed intentionally removed. The `reports` table starts
// empty and only populates from real uploads via the UploadModal.

