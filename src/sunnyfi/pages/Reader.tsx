import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  fetchReportById, fetchReports, fetchReportHtml, setReportStar,
  typeLabel, secLabel,
  type ReportRow,
} from "@/sunnyfi/lib/research";
import { supabase } from "@/integrations/supabase/client";

interface TocEntry {
  id: string;
  title: string;
  level: 1 | 2;
  parent: string | null; // top-section id (for sub rows)
  index: number;         // display number (1-based) for level-1 rows, 0 for sub rows
}

const STATIC_SIGNALS: { k: string; v: string; cls?: "pos" | "neg" | "neon" }[] = [
  { k: "Conviction", v: "—", cls: "neon" },
  { k: "Direction",  v: "—", cls: "pos"  },
  { k: "Time frame", v: "—" },
  { k: "Fair value", v: "—" },
  { k: "Catalyst",   v: "—" },
];

export default function Reader() {
  const { id = "" } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const { data: report, isLoading, error } = useQuery({
    queryKey: ["report", id],
    queryFn: () => fetchReportById(id),
    enabled: !!id,
  });

  const { data: allReports = [] } = useQuery({
    queryKey: ["reports"],
    queryFn: fetchReports,
  });

  // Prev / next in the same sector
  const [prev, next] = useMemo<[ReportRow | null, ReportRow | null]>(() => {
    if (!report || allReports.length === 0) return [null, null];
    const peers = allReports.filter((r) => r.sec === report.sec);
    const idx = peers.findIndex((r) => r.id === report.id);
    if (idx < 0) return [null, null];
    return [peers[idx - 1] ?? null, peers[idx + 1] ?? null];
  }, [report, allReports]);

  const [html, setHtml] = useState<string | null>(null);
  const [htmlError, setHtmlError] = useState<string | null>(null);
  useEffect(() => {
    if (!report) return;
    setHtml(null); setHtmlError(null);
    let cancelled = false;
    fetchReportHtml(report.file_path)
      .then((h) => { if (!cancelled) setHtml(h); })
      .catch((e) => { if (!cancelled) setHtmlError(e instanceof Error ? e.message : "Couldn't load report"); });
    return () => { cancelled = true; };
  }, [report]);

  // Notes rail toggle (persisted)
  const [notesOn, setNotesOn] = useState<boolean>(() => localStorage.getItem("rr-notes-visible") === "1");
  useEffect(() => { localStorage.setItem("rr-notes-visible", notesOn ? "1" : "0"); }, [notesOn]);

  // Local starred state, mirrors DB. Optimistic.
  const [starred, setStarred] = useState(false);
  useEffect(() => { if (report) setStarred(!!report.star); }, [report]);
  const toggleStar = async () => {
    if (!report) return;
    const next = !starred;
    setStarred(next);
    try {
      await setReportStar(report.id, next);
      queryClient.invalidateQueries({ queryKey: ["reports"] });
      queryClient.invalidateQueries({ queryKey: ["report", report.id] });
    } catch (e) {
      setStarred(!next);
      toast.error(e instanceof Error ? e.message : "Couldn't star");
    }
  };

  // Notes (localStorage, debounced)
  const noteKey = `rr-note-${id}`;
  const [note, setNote] = useState("");
  const [noteStatus, setNoteStatus] = useState<string>("empty");
  const noteStatusSaved = noteStatus.startsWith("saved");
  useEffect(() => { setNote(localStorage.getItem(noteKey) || ""); }, [noteKey]);
  useEffect(() => {
    if (!note.trim()) { setNoteStatus("empty"); return; }
    setNoteStatus("typing…");
    const t = setTimeout(() => {
      localStorage.setItem(noteKey, note);
      const time = new Date().toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }).toLowerCase();
      setNoteStatus("saved · " + time);
    }, 400);
    return () => clearTimeout(t);
  }, [note, noteKey]);
  const wordCount = useMemo(() => (note.trim().match(/\S+/g) || []).length, [note]);

  // TOC + scroll tracking from iframe
  const iframeRef = useRef<HTMLIFrameElement | null>(null);
  const [sections, setSections] = useState<TocEntry[]>([]);
  const sectionElsRef = useRef<Record<string, HTMLElement>>({});
  const [pct, setPct] = useState(0);
  const [activeId, setActiveId] = useState<string | null>(null);

  const absTop = (el: HTMLElement) => {
    let y = 0;
    let n: HTMLElement | null = el;
    while (n) { y += n.offsetTop; n = n.offsetParent as HTMLElement | null; }
    return y;
  };

  const onIframeScroll = useCallback(() => {
    const iframe = iframeRef.current;
    const win = iframe?.contentWindow;
    const doc = iframe?.contentDocument;
    if (!win || !doc) return;
    localStorage.setItem(`rr-scroll-${id}`, String(win.scrollY));
    const total = doc.documentElement.scrollHeight - win.innerHeight;
    const p = total > 0 ? Math.min(1, Math.max(0, win.scrollY / total)) : 0;
    setPct(p);
    const anchor = win.scrollY + 80;
    let active: TocEntry | null = null;
    for (const s of sections) {
      const el = sectionElsRef.current[s.id];
      if (!el) continue;
      if (absTop(el) <= anchor) active = s;
      else break;
    }
    setActiveId(active?.id ?? null);
  }, [sections, id]);

  // Wire up iframe scroll + TOC extraction after it loads.
  const onIframeLoad = () => {
    const iframe = iframeRef.current;
    if (!iframe) return;
    const win = iframe.contentWindow;
    const doc = iframe.contentDocument;
    if (!win || !doc) return;

    // Restore scroll
    const savedScroll = parseFloat(localStorage.getItem(`rr-scroll-${id}`) || "0");
    if (savedScroll > 0) win.scrollTo(0, savedScroll);

    // Extract TOC: section[id] with optional h2[id] children.
    const topSections = Array.from(doc.querySelectorAll("section[id]")) as HTMLElement[];
    const entries: TocEntry[] = [];
    const elMap: Record<string, HTMLElement> = {};
    topSections.forEach((sec, i) => {
      const h1 = sec.querySelector("h1, .section-h") as HTMLElement | null;
      const tag = sec.querySelector(".section-tag") as HTMLElement | null;
      const label = (h1?.textContent || tag?.textContent || sec.id).trim();
      entries.push({ id: sec.id, title: label, level: 1, parent: null, index: i + 1 });
      elMap[sec.id] = sec;
      sec.querySelectorAll("h2[id]").forEach((h2El) => {
        const h2 = h2El as HTMLElement;
        entries.push({
          id: h2.id,
          title: h2.textContent?.replace(/^\s*\d+(\.\d+)*\s*/, "").trim() || h2.id,
          level: 2,
          parent: sec.id,
          index: 0,
        });
        elMap[h2.id] = h2;
      });
    });
    sectionElsRef.current = elMap;
    setSections(entries);

    win.addEventListener("scroll", onIframeScroll, { passive: true });
    onIframeScroll();
  };

  // Rewire scroll listener when `sections` updates (since callback is memoized on it).
  useEffect(() => {
    const win = iframeRef.current?.contentWindow;
    if (!win) return;
    win.addEventListener("scroll", onIframeScroll, { passive: true });
    onIframeScroll();
    return () => win.removeEventListener("scroll", onIframeScroll);
  }, [sections, onIframeScroll]);

  // Suppress benign ResizeObserver warning from iframe-hosted content.
  useEffect(() => {
    const onErr = (e: ErrorEvent) => {
      if (e.message && e.message.includes("ResizeObserver loop")) e.stopImmediatePropagation();
    };
    window.addEventListener("error", onErr, true);
    return () => window.removeEventListener("error", onErr, true);
  }, []);

  // Keyboard: J/K sections, N/P reports, Esc back
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      if (e.key === "Escape") { navigate("/research"); return; }
      if (e.key === "n" || e.key === "N") { if (next) navigate(`/research/reports/${next.id}`); return; }
      if (e.key === "p" || e.key === "P") { if (prev) navigate(`/research/reports/${prev.id}`); return; }
      const win = iframeRef.current?.contentWindow;
      if (!win || sections.length === 0) return;
      const y = win.scrollY + 40;
      if (e.key === "j" || e.key === "J") {
        const nxt = sections.find((s) => {
          const el = sectionElsRef.current[s.id];
          return el && absTop(el) > y + 20;
        });
        if (nxt) {
          const el = sectionElsRef.current[nxt.id];
          el?.scrollIntoView({ behavior: "smooth", block: "start" });
        }
      }
      if (e.key === "k" || e.key === "K") {
        const prv = [...sections].reverse().find((s) => {
          const el = sectionElsRef.current[s.id];
          return el && absTop(el) < y - 20;
        });
        if (prv) {
          const el = sectionElsRef.current[prv.id];
          el?.scrollIntoView({ behavior: "smooth", block: "start" });
        }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [navigate, sections, next, prev]);

  const onTocClick = (s: TocEntry) => {
    const el = sectionElsRef.current[s.id];
    el?.scrollIntoView({ behavior: "smooth", block: "start" });
  };

  const onCopyLink = async () => {
    try {
      await navigator.clipboard.writeText(window.location.href);
      toast.success("Link copied");
    } catch {
      toast.error("Couldn't copy link");
    }
  };

  const onPrint = () => {
    iframeRef.current?.contentWindow?.print();
  };

  const onDownload = async () => {
    if (!report?.file_path || !html) return;
    const blob = new Blob([html], { type: "text/html" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${report.title.replace(/[^\w\- ]+/g, "_")}.html`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const onOpenRaw = () => {
    if (!report?.file_path) return;
    const { data } = supabase.storage.from("reports").getPublicUrl(report.file_path);
    if (data.publicUrl) window.open(data.publicUrl, "_blank", "noopener,noreferrer");
  };

  // Related — other reports with the same primary ticker
  const related = useMemo(() => {
    if (!report || !report.tickers[0]) return [];
    const t = report.tickers[0];
    return allReports.filter((r) => r.id !== report.id && r.tickers.includes(t)).slice(0, 5);
  }, [report, allReports]);

  if (isLoading) return <div className="rr-shell rr-loading">Loading…</div>;
  if (error || !report) {
    return (
      <div className="rr-shell rr-loading">
        <div className="rr-loading-text">Couldn't find that report.</div>
        <Link to="/research" className="back"><span className="arrow">←</span><span>Back to Research</span></Link>
      </div>
    );
  }

  const primaryTicker = report.tickers[0] ?? report.typ.toUpperCase();
  const dateLabel = report.d;
  const sectorLabel = secLabel[report.sec] ?? report.sec;

  return (
    <div className="rr-shell">
      {/* Top chrome */}
      <div className="rr-top">
        <Link to="/research" className="back">
          <span className="arrow">←</span>
          <span>Research</span>
        </Link>
        <div className="top-div" />
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span className="meta-ticker">{primaryTicker}</span>
            <span className={"badge " + report.typ}>{typeLabel[report.typ]}</span>
            <span className="meta-title" title={report.title}>{report.title}</span>
          </div>
          <div className="meta-sub">
            <span>{report.author}</span><span className="dot" />
            <span>{dateLabel}</span><span className="dot" />
            <span>{report.read} read</span><span className="dot" />
            <span>{sectorLabel}</span>
          </div>
        </div>
        <div className="top-spacer" />
        <div className="top-actions">
          <button className={"ico-btn star" + (starred ? " on" : "")} onClick={toggleStar} title="Star">
            {starred ? "★" : "☆"}
          </button>
          <button className="ico-btn" onClick={onCopyLink} title="Copy link">⎘</button>
          <button className="ico-btn" onClick={onPrint} title="Print">⎙</button>
          <button
            className={"top-btn" + (notesOn ? " neon" : "")}
            onClick={() => setNotesOn((v) => !v)}
            title="Toggle notes rail"
          >
            ☰ Notes
          </button>
          <button className="top-btn" onClick={onDownload} title="Download">↓ Download</button>
          <button className="top-btn" onClick={onOpenRaw} title="Open raw in new tab">↗ Open raw</button>
        </div>
      </div>

      {/* Progress bar */}
      <div className="rr-progress">
        <div className="rr-progress-fill" style={{ width: (pct * 100).toFixed(1) + "%" }} />
      </div>

      {/* 3-column body */}
      <div className={"rr-body" + (notesOn ? " with-side" : "")}>
        {/* TOC */}
        <aside className="toc">
          <div className="toc-head">
            <span>Contents</span>
            <span className="pct">{Math.round(pct * 100)}%</span>
          </div>
          <div>
            {sections.length === 0 && (
              <div className="rr-empty">
                <div className="icon">⋯</div>
                <div>{html ? "No table of contents in this report." : "Loading table of contents…"}</div>
              </div>
            )}
            {(() => {
              let topIdx = 0;
              let currentParentId: string | null = null;
              const activeTopId = (() => {
                if (!activeId) return null;
                const active = sections.find((s) => s.id === activeId);
                if (!active) return null;
                return active.level === 1 ? active.id : active.parent;
              })();
              const activeIndex = sections.findIndex((s) => s.id === activeId);
              return sections.map((s, i) => {
                if (s.level === 1) { topIdx += 1; currentParentId = s.id; }
                const isSub = s.level === 2;
                const revealSub = isSub && s.parent === activeTopId;
                const on = s.id === activeId;
                const visited = activeIndex > -1 && i < activeIndex;
                const cls = ["toc-item"];
                if (isSub) cls.push("sub");
                if (isSub && revealSub) cls.push("reveal");
                if (on) cls.push("on");
                if (visited) cls.push("visited");
                return (
                  <div
                    key={s.id}
                    className={cls.join(" ")}
                    onClick={() => onTocClick(s)}
                    data-parent={isSub ? currentParentId ?? undefined : undefined}
                  >
                    <span className="num">{s.level === 1 ? String(topIdx).padStart(2, "0") : ""}</span>
                    <span className="lbl" title={s.title}>{s.title}</span>
                  </div>
                );
              });
            })()}
          </div>
        </aside>

        {/* Reader iframe */}
        <div className="reader-wrap">
          {htmlError && (
            <div className="rr-empty">
              <div className="icon">!</div>
              <div>{htmlError}</div>
            </div>
          )}
          {!htmlError && html && (
            <iframe
              ref={iframeRef}
              className="reader-frame"
              title={report.title}
              srcDoc={html}
              sandbox="allow-same-origin allow-scripts allow-popups allow-forms"
              onLoad={onIframeLoad}
            />
          )}
        </div>

        {/* Notes rail */}
        <aside className="side">
          <div className="side-block">
            <div className="side-label">
              <span>My take</span>
              <span className={"status" + (noteStatusSaved ? " saved" : "")}>{noteStatus}</span>
            </div>
            <textarea
              className="note-area"
              placeholder="Jot down your read. Private to you, auto-saved."
              value={note}
              onChange={(e) => setNote(e.target.value)}
              onKeyDown={(e) => {
                if ((e.metaKey || e.ctrlKey) && e.key === "s") {
                  e.preventDefault();
                  localStorage.setItem(noteKey, note);
                  const time = new Date().toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }).toLowerCase();
                  setNoteStatus("saved · " + time);
                }
              }}
            />
            <div className="note-foot">
              <div className="shortcuts">
                <span><kbd>⌘S</kbd>save</span>
                <span><kbd>⌘/</kbd>quote selection</span>
              </div>
              <span>{wordCount} {wordCount === 1 ? "word" : "words"}</span>
            </div>
          </div>

          <div className="side-block">
            <div className="side-label"><span>Signals</span></div>
            <div className="sig-list">
              {STATIC_SIGNALS.map((s) => (
                <div className="sig" key={s.k}>
                  <span className="k">{s.k}</span>
                  <span className={"v" + (s.cls ? " " + s.cls : "")}>{s.v}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="side-block">
            <div className="side-label"><span>Tags</span></div>
            <div className="tag-list">
              <span className="tag neon">{sectorLabel}</span>
              {report.tags.map((t) => (
                <span className="tag" key={t}>#{t}</span>
              ))}
            </div>
          </div>

          <div className="side-block">
            <div className="side-label"><span>Related · same ticker</span></div>
            {related.length === 0 && (
              <div style={{ color: "var(--navi-fg4)", fontSize: 12 }}>No related reports yet.</div>
            )}
            {related.map((r) => (
              <div
                className="related-item"
                key={r.id}
                onClick={() => navigate(`/research/reports/${r.id}`)}
              >
                <span className="date">{r.d.replace(" ", "·")}</span>
                <span className="title">
                  <span style={{ fontFamily: "var(--navi-font-mono)", color: "var(--navi-fg1)", marginRight: 6 }}>
                    {r.tickers[0] ?? "—"}
                  </span>
                  {r.title}
                </span>
                <span className="arr">↗</span>
              </div>
            ))}
          </div>
        </aside>
      </div>

      {/* Bottom bar */}
      <div className="rr-foot">
        <span><kbd>J</kbd>next section</span>
        <span><kbd>K</kbd>prev section</span>
        <span className="sep">·</span>
        <span><kbd>N</kbd>next report</span>
        <span><kbd>P</kbd>prev report</span>
        <span className="sep">·</span>
        <span><kbd>Esc</kbd>back to hub</span>
        <div className="foot-spacer" />
        {prev && (
          <a
            className="foot-nav"
            title={`Previous report in ${sectorLabel}`}
            onClick={() => navigate(`/research/reports/${prev.id}`)}
          >
            <span className="arr">←</span>
            <span className="tick">{prev.tickers[0] ?? "—"}</span>
            <span>{prev.title}</span>
          </a>
        )}
        {next && (
          <a
            className="foot-nav"
            title={`Next report in ${sectorLabel}`}
            onClick={() => navigate(`/research/reports/${next.id}`)}
          >
            <span className="tick">{next.tickers[0] ?? "—"}</span>
            <span>{next.title}</span>
            <span className="arr">→</span>
          </a>
        )}
      </div>
    </div>
  );
}
