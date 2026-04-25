import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import type { ReportType, Visibility } from "@/sunnyfi/lib/research";

const UP_SECTORS = [
  "Technology", "Energy", "Financials", "Healthcare", "Macro",
  "Industrials", "Staples", "Consumer", "Materials", "Utilities",
  "Real estate", "Communications",
];
const UP_TYPES: { k: ReportType; label: string; hint: string }[] = [
  { k: "single", label: "Single-stock", hint: "One ticker, deep dive" },
  { k: "macro",  label: "Macro",        hint: "No single name" },
  { k: "theme",  label: "Thematic",     hint: "Cross-sector idea" },
  { k: "earn",   label: "Earnings",     hint: "Tied to a print" },
];
const UP_VIS: Visibility[] = ["Team", "Firm-wide", "Private"];

type Stage = "empty" | "ready";
interface FileInfo { name: string; size: number; file: File }

interface DropzoneProps {
  file: FileInfo | null;
  setFile: (f: FileInfo | null) => void;
  stage: Stage;
  setStage: (s: Stage) => void;
}

function Dropzone({ file, setFile, stage, setStage }: DropzoneProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [drag, setDrag] = useState(false);

  const accept = (f?: File) => {
    if (!f) return;
    const isHtml = /\.html?$/i.test(f.name) || f.type === "text/html" || f.type === "";
    if (!isHtml) {
      toast.error(`Only HTML files are supported (got ${f.name})`);
      return;
    }
    setFile({ name: f.name, size: f.size, file: f });
    setStage("ready");
  };

  // While the modal is open, swallow drag/drop at the window level so the
  // browser doesn't navigate to open the file if the user drops off-target.
  useEffect(() => {
    const prevent = (e: DragEvent) => {
      // Only prevent when a file is being dragged
      if (e.dataTransfer?.types?.includes("Files")) e.preventDefault();
    };
    window.addEventListener("dragover", prevent);
    window.addEventListener("drop", prevent);
    return () => {
      window.removeEventListener("dragover", prevent);
      window.removeEventListener("drop", prevent);
    };
  }, []);

  return (
    <div
      className={"up-drop" + (drag ? " drag" : "") + (file ? " has" : "")}
      onDragOver={(e) => { e.preventDefault(); e.stopPropagation(); setDrag(true); }}
      onDragEnter={(e) => { e.preventDefault(); e.stopPropagation(); setDrag(true); }}
      onDragLeave={(e) => { e.preventDefault(); e.stopPropagation(); setDrag(false); }}
      onDrop={(e) => {
        e.preventDefault();
        e.stopPropagation();
        setDrag(false);
        accept(e.dataTransfer.files?.[0]);
      }}
      onClick={() => !file && inputRef.current?.click()}
    >
      <input
        ref={inputRef}
        type="file"
        style={{ display: "none" }}
        accept=".html,.htm,text/html"
        onChange={(e) => accept(e.target.files?.[0])}
      />
      {!file && (
        <>
          <div className="up-drop-ico">↑</div>
          <div className="up-drop-head">Drop a report here, or <span className="up-link">browse</span></div>
          <div className="up-drop-sub">HTML only · up to 50 MB</div>
        </>
      )}
      {file && (
        <div className="up-file">
          <div className="up-file-ico">▤</div>
          <div className="up-file-meta">
            <div className="up-file-name">{file.name}</div>
            <div className="up-file-sub">
              {Math.max(1, Math.round((file.size || 840000) / 1024))} KB
              <span className="up-sep">·</span>
              {stage === "ready" && <span style={{ color: "var(--navi-positive)" }}>✓ Ready to review</span>}
            </div>
          </div>
          <button className="up-file-x" onClick={(e) => { e.stopPropagation(); setFile(null); setStage("empty"); }}>✕</button>
        </div>
      )}
    </div>
  );
}

interface UploadModalProps {
  open: boolean;
  onClose: () => void;
  onPublished: () => void;
}

export default function UploadModal({ open, onClose, onPublished }: UploadModalProps) {
  const [file, setFile] = useState<FileInfo | null>(null);
  const [stage, setStage] = useState<Stage>("empty");
  const [title, setTitle] = useState("");
  const [tickers, setTickers] = useState<string[]>([]);
  const [tickerDraft, setTickerDraft] = useState("");
  const [rtype, setRtype] = useState<ReportType>("single");
  const [sectors, setSectors] = useState<string[]>([]);
  const [author, setAuthor] = useState("Team");
  const [pubDate, setPubDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [tags, setTags] = useState<string[]>([]);
  const [tagDraft, setTagDraft] = useState("");
  const [vis, setVis] = useState<Visibility>("Team");
  const [addToWatch, setAddToWatch] = useState(true);
  const [notify, setNotify] = useState(true);
  const [summary, setSummary] = useState("");
  const [publishing, setPublishing] = useState(false);

  useEffect(() => {
    if (!open) return;
    setFile(null); setStage("empty");
    setTitle(""); setTickers([]); setTickerDraft("");
    setRtype("single"); setSectors([]); setTags([]); setTagDraft("");
    setSummary(""); setVis("Team"); setAddToWatch(true); setNotify(true);
  }, [open]);

  useEffect(() => {
    if (stage !== "ready" || !file) return;
    if (!title) {
      const stem = (file.name || "").replace(/\.[a-z]+$/i, "");
      setTitle(stem.replace(/[_\-]+/g, " ").replace(/\s+/g, " ").trim());
    }
  }, [stage, file, title]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  const canPublish = !!file && stage === "ready" && title.trim().length > 0 && sectors.length > 0;

  const toggleSector = (s: string) =>
    setSectors((xs) => (xs.includes(s) ? xs.filter((x) => x !== s) : [...xs, s]));

  const addTicker = () => {
    const t = tickerDraft.trim().toUpperCase();
    if (!t) return;
    if (!tickers.includes(t)) setTickers([...tickers, t]);
    setTickerDraft("");
  };
  const addTag = () => {
    const t = tagDraft.trim();
    if (!t) return;
    if (!tags.includes(t)) setTags([...tags, t]);
    setTagDraft("");
  };

  const handlePublish = async () => {
    if (!file || !canPublish) return;
    setPublishing(true);
    try {
      const ext = (file.name.match(/\.html?$/i)?.[0] || ".html").toLowerCase();
      const path = `${crypto.randomUUID()}${ext}`;
      // Re-wrap the File as a Blob with explicit text/html type — some
      // browsers/OSes give the File an empty `.type` and Supabase then
      // serves it as text/plain, which the browser renders as source.
      const blob = new Blob([await file.file.arrayBuffer()], { type: "text/html" });
      const { error: upErr } = await supabase.storage
        .from("reports")
        .upload(path, blob, { contentType: "text/html", upsert: false });
      if (upErr) throw upErr;

      const readMin = Math.max(3, Math.round((summary.length + 200) / 40));
      const { error: insErr } = await supabase.from("reports").insert({
        title: title.trim(),
        tickers,
        report_type: rtype,
        primary_sector: sectors[0] ?? null,
        sectors,
        author,
        published_at: pubDate,
        read_minutes: readMin,
        tags,
        summary,
        visibility: vis,
        file_path: path,
        starred: false,
      });
      if (insErr) throw insErr;

      toast.success("Report published");
      onPublished();
      onClose();
    } catch (e) {
      console.error(e);
      toast.error("Failed to publish report");
    } finally {
      setPublishing(false);
    }
  };

  return (
    <div className="up-backdrop" onClick={onClose}>
      <div className="up-panel" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <div className="up-head">
          <div>
            <div className="section-label" style={{ marginBottom: 4 }}>New · upload</div>
            <h2 className="up-h1">Upload report</h2>
          </div>
          <button className="up-close" onClick={onClose} aria-label="Close">✕</button>
        </div>

        <div className="up-body">
          <div className="up-col">
            <div className="up-section-label">File</div>
            <Dropzone file={file} setFile={setFile} stage={stage} setStage={setStage} />

            {stage === "ready" && (
              <>
                <div className="up-field" style={{ marginTop: 20 }}>
                  <label className="up-label">Title <span className="up-req">required</span></label>
                  <input className="up-input" value={title} onChange={(e) => setTitle(e.target.value)}
                         placeholder="e.g. Apple — services margin expansion…" />
                </div>

                <div className="up-field">
                  <label className="up-label">Executive summary <span className="up-optional">optional</span></label>
                  <textarea className="up-input up-textarea" value={summary} onChange={(e) => setSummary(e.target.value)}
                            rows={3} placeholder="One-sentence thesis the reader will see in the row preview." />
                </div>

                <div className="up-grid-2">
                  <div className="up-field">
                    <label className="up-label">Author</label>
                    <input className="up-input" value={author} onChange={(e) => setAuthor(e.target.value)} />
                  </div>
                  <div className="up-field">
                    <label className="up-label">Publish date</label>
                    <input className="up-input" type="date" value={pubDate} onChange={(e) => setPubDate(e.target.value)} />
                  </div>
                </div>
              </>
            )}
          </div>

          <div className="up-col">
            <div className="up-section-label">Classification</div>

            <div className="up-field">
              <label className="up-label">Report type</label>
              <div className="up-type-grid">
                {UP_TYPES.map((t) => (
                  <button key={t.k} className={"up-type" + (rtype === t.k ? " on" : "")} onClick={() => setRtype(t.k)}>
                    <span className={"badge " + t.k} style={{ justifySelf: "start", marginBottom: 6 }}>{t.label}</span>
                    <span className="up-type-hint">{t.hint}</span>
                  </button>
                ))}
              </div>
            </div>

            <div className="up-field">
              <label className="up-label">
                Tickers
                {rtype === "single" && <span className="up-req">required</span>}
                {rtype !== "single" && <span className="up-optional">optional</span>}
              </label>
              <div className="up-chips">
                {tickers.map((t) => (
                  <span key={t} className="up-chip mono">
                    {t}
                    <button className="up-chip-x" onClick={() => setTickers(tickers.filter((x) => x !== t))}>✕</button>
                  </span>
                ))}
                <input
                  className="up-chip-input"
                  placeholder={tickers.length ? "+ add" : "AAPL, NVDA…"}
                  value={tickerDraft}
                  onChange={(e) => setTickerDraft(e.target.value.toUpperCase())}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === "," || e.key === " ") { e.preventDefault(); addTicker(); }
                    if (e.key === "Backspace" && !tickerDraft && tickers.length) setTickers(tickers.slice(0, -1));
                  }}
                />
              </div>
            </div>

            <div className="up-field">
              <label className="up-label">
                Sectors <span className="up-req">required</span>
                {sectors.length > 0 && <span className="up-count">· {sectors.length} selected</span>}
              </label>
              <div className="up-sector-grid">
                {UP_SECTORS.map((s) => (
                  <button key={s} className={"up-sector-chip" + (sectors.includes(s) ? " on" : "")} onClick={() => toggleSector(s)}>{s}</button>
                ))}
              </div>
            </div>

            <div className="up-field">
              <label className="up-label">Tags <span className="up-optional">optional</span></label>
              <div className="up-chips">
                {tags.map((t) => (
                  <span key={t} className="up-chip">
                    #{t}
                    <button className="up-chip-x" onClick={() => setTags(tags.filter((x) => x !== t))}>✕</button>
                  </span>
                ))}
                <input
                  className="up-chip-input"
                  placeholder={tags.length ? "+ add" : "margin, capex, IV crush…"}
                  value={tagDraft}
                  onChange={(e) => setTagDraft(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === ",") { e.preventDefault(); addTag(); }
                    if (e.key === "Backspace" && !tagDraft && tags.length) setTags(tags.slice(0, -1));
                  }}
                />
              </div>
            </div>

            <div className="up-field">
              <label className="up-label">Visibility</label>
              <div className="up-seg">
                {UP_VIS.map((v) => (
                  <button key={v} className={"up-seg-btn" + (vis === v ? " on" : "")} onClick={() => setVis(v)}>{v}</button>
                ))}
              </div>
            </div>

            <div className="up-toggles">
              <label className="up-toggle">
                <input type="checkbox" checked={addToWatch} onChange={(e) => setAddToWatch(e.target.checked)} />
                <span>Add tickers to my watchlist</span>
              </label>
              <label className="up-toggle">
                <input type="checkbox" checked={notify} onChange={(e) => setNotify(e.target.checked)} />
                <span>Notify team on publish</span>
              </label>
            </div>
          </div>
        </div>

        {stage === "ready" && (
          <div className="up-preview">
            <div className="up-section-label">Preview · this is how it will appear in the list</div>
            <div className="up-preview-row">
              <div className="rep new" style={{ cursor: "default", borderBottom: "none" }}>
                <div className="rep-bar" />
                <div className="rep-star">☆</div>
                <div className="rep-date">
                  {new Date(pubDate).toLocaleString("en-US", { month: "short", day: "numeric" })}
                </div>
                <div className={"rep-ticker" + (!tickers.length ? " dash" : "")}>{tickers[0] || "—"}</div>
                <div className={"badge " + rtype}>{UP_TYPES.find((t) => t.k === rtype)?.label || "Single"}</div>
                <div className="rep-title">
                  <span className="rep-newdot" />
                  {title || <span style={{ color: "var(--navi-fg4)" }}>Title will appear here…</span>}
                </div>
                <div className="rep-author">{author}</div>
                <div className="rep-read">{Math.max(3, Math.round((summary.length + 200) / 40))}m</div>
                <div className="rep-open">↗</div>
              </div>
            </div>
          </div>
        )}

        <div className="up-foot">
          <div className="up-foot-meta">
            <kbd>Esc</kbd> to close
            <span className="up-sep">·</span>
            <kbd>⌘↵</kbd> to publish
          </div>
          <div style={{ flex: 1 }} />
          <button className="up-btn ghost" onClick={onClose}>Cancel</button>
          <button className="up-btn tinted" disabled={!file}>Save draft</button>
          <button
            className="up-btn primary"
            disabled={!canPublish || publishing}
            onClick={handlePublish}
          >
            {publishing ? "Publishing…" : "✓ Publish report"}
          </button>
        </div>
      </div>
    </div>
  );
}
