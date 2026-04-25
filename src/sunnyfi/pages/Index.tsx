import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  SECTORS, TYPES, RECENCY, VIEWS,
  typeLabel, groupRows, fetchReports, deleteReport,
  type ReportRow, type ReportType, type SectorKey, type ViewKey,
} from "@/sunnyfi/lib/research";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import UploadModal from "@/sunnyfi/components/research/UploadModal";

function Brand() {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
      <div className="brand">
        <span className="brand-txt">Research Hub</span>
        <span className="cursor" />
      </div>
    </div>
  );
}

function Header({ onUpload }: { onUpload: () => void }) {
  return (
    <div className="hdr">
      <Brand />
      <div className="hdr-spacer" />
      <div className="hdr-search">
        <span style={{ color: "var(--navi-fg4)" }}>⌕</span>
        <input placeholder="Search title, ticker, author…" />
        <kbd>⌘K</kbd>
      </div>
      <button className="hdr-btn" onClick={onUpload}>↑ Upload report</button>
    </div>
  );
}

interface RailProps {
  sector: SectorKey | "all"; setSector: (v: SectorKey | "all") => void;
  rtype: ReportType | "all"; setRtype: (v: ReportType | "all") => void;
  recency: string; setRecency: (v: string) => void;
  starred: boolean; setStarred: (v: boolean) => void;
  unread: boolean; setUnread: (v: boolean) => void;
}

function Rail({ sector, setSector, rtype, setRtype, recency, setRecency, starred, setStarred, unread, setUnread }: RailProps) {
  return (
    <aside className="rail">
      <div className="rail-section">
        <div className="section-label">Sector</div>
        {SECTORS.map((s) => (
          <div key={s.k} className={"rail-item" + (s.k === sector ? " on" : "")} onClick={() => setSector(s.k)}>
            <span>{s.label}</span>
            <span className="count">{s.count}</span>
          </div>
        ))}
      </div>

      <div className="rail-section">
        <div className="section-label">Type</div>
        {TYPES.map((s) => (
          <div key={s.k} className={"rail-item" + (s.k === rtype ? " on" : "")} onClick={() => setRtype(s.k)}>
            <span>{s.label}</span>
            <span className="count">{s.count}</span>
          </div>
        ))}
      </div>

      <div className="rail-section">
        <div className="section-label">Recency</div>
        {RECENCY.map((s) => (
          <div key={s.k} className={"rail-item" + (s.k === recency ? " on" : "")} onClick={() => setRecency(s.k)}>
            <span>{s.label}</span>
            <span className="count">{s.count}</span>
          </div>
        ))}
      </div>

      <div className="rail-section">
        <div className="section-label">Show</div>
        <div className={"rail-check" + (starred ? " on" : "")} onClick={() => setStarred(!starred)}>
          <span className="box">{starred ? "✓" : ""}</span>
          <span>Starred only</span>
        </div>
        <div className={"rail-check" + (unread ? " on" : "")} onClick={() => setUnread(!unread)}>
          <span className="box">{unread ? "✓" : ""}</span>
          <span>Unread only</span>
        </div>
      </div>
    </aside>
  );
}

function ViewSwitcher({ view, setView }: { view: ViewKey; setView: (v: ViewKey) => void }) {
  return (
    <div className="views" role="tablist">
      {VIEWS.map((v) => (
        <button
          key={v.k}
          role="tab"
          aria-selected={v.k === view}
          className={"view-tab" + (view === v.k ? " on" : "")}
          onClick={() => setView(v.k)}
        >
          <span>{v.label}</span>
          {v.count != null && <span className="c">{v.count}</span>}
        </button>
      ))}
      <div style={{ flex: 1 }} />
      <div style={{ fontFamily: "var(--navi-font-mono)", fontSize: 10, color: "var(--navi-fg4)", paddingRight: 6 }}>
        sort: date ↓
      </div>
    </div>
  );
}

function Row({ r, onStar, onOpen, onDelete }: {
  r: ReportRow;
  onStar: () => void;
  onOpen: () => void;
  onDelete: () => void;
}) {
  const primary = r.tickers[0] ?? "—";
  const dash = primary === "—";
  return (
    <div
      className={"rep " + r.fresh}
      onClick={onOpen}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === "Enter") onOpen(); }}
    >
      <div className="rep-bar" />
      <div
        className={"rep-star" + (r.star ? " on" : "")}
        onClick={(e) => { e.stopPropagation(); onStar(); }}
        role="button"
        aria-label={r.star ? "Unstar" : "Star"}
      >
        {r.star ? "★" : "☆"}
      </div>
      <div className="rep-date">{r.d}</div>
      <div className={"rep-ticker" + (dash ? " dash" : "")}>{primary}</div>
      <div className={"badge " + r.typ}>{typeLabel[r.typ]}</div>
      <div className="rep-title">
        {r.fresh === "new" && <span className="rep-newdot" />}
        {r.title}
      </div>
      <div className="rep-author">{r.author}</div>
      <div className="rep-read">{r.read}</div>
      <div className="rep-actions">
        <button
          className="rep-delete"
          onClick={(e) => { e.stopPropagation(); onDelete(); }}
          aria-label="Delete report"
          title="Delete"
        >
          ✕
        </button>
        <span className="rep-open" aria-hidden>↗</span>
      </div>
    </div>
  );
}

function ColumnHead() {
  return (
    <div className="cols">
      <span />
      <span />
      <span>Date</span>
      <span>Ticker</span>
      <span>Type</span>
      <span>Title</span>
      <span>Author</span>
      <span style={{ textAlign: "right" }}>Read</span>
      <span />
    </div>
  );
}

function SubHeader({ view }: { view: ViewKey }) {
  const titles: Record<ViewKey, { h1: string }> = {
    latest:  { h1: "Latest research" },
    sector:  { h1: "By sector" },
    author:  { h1: "By author" },
    type:    { h1: "By type" },
    starred: { h1: "Starred" },
  };
  const meta = titles[view] || titles.latest;
  return (
    <div className="sub">
      <div><h1>{meta.h1}</h1></div>
    </div>
  );
}

function Banner({ rows }: { rows: ReportRow[] }) {
  if (!rows.length) return null;
  const recent = rows.slice(0, 8);
  const summary = `${rows.length} report${rows.length === 1 ? "" : "s"} in the hub`;

  const items = (
    <>
      <span className="banner-alert">◆ {summary}</span>
      <span className="banner-sep">·········</span>
      {recent.map((r, i) => (
        <span key={r.id} style={{ display: "inline-flex", alignItems: "center" }}>
          <span className="banner-item">
            <span className="k">{r.tickers[0] ?? r.typ.toUpperCase()}</span>{" "}
            <span className="v">{r.title}</span>
          </span>
          {i < recent.length - 1 && <span className="banner-sep">·</span>}
        </span>
      ))}
      <span className="banner-sep">·········</span>
    </>
  );
  return (
    <div className="banner">
      <div className="banner-track">{items}{items}</div>
    </div>
  );
}

export default function Index() {
  const [view, setView] = useState<ViewKey>(() => {
    const saved = localStorage.getItem("rh-view") as ViewKey | null;
    return saved && ["latest", "sector", "author", "type", "starred"].includes(saved) ? saved : "latest";
  });
  const [sector, setSector] = useState<SectorKey | "all">("all");
  const [rtype, setRtype] = useState<ReportType | "all">("all");
  const [recency, setRecency] = useState("7d");
  const [starredOnly, setStarredOnly] = useState(false);
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const navigate = useNavigate();

  const queryClient = useQueryClient();

  useEffect(() => { localStorage.setItem("rh-view", view); }, [view]);

  const { data: rows = [] } = useQuery({
    queryKey: ["reports"],
    queryFn: () => fetchReports(),
  });

  const filtered = useMemo(
    () =>
      rows.filter((r) => {
        if (sector !== "all" && r.sec !== sector) return false;
        if (rtype !== "all" && r.typ !== rtype) return false;
        if (starredOnly && !r.star) return false;
        if (unreadOnly && r.fresh === "read") return false;
        return true;
      }),
    [rows, sector, rtype, starredOnly, unreadOnly],
  );

  const groups = useMemo(() => groupRows(filtered, view), [filtered, view]);
  const shownCount = groups.reduce((a, g) => a + g.items.length, 0);

  const toggleStar = async (id: string, current: boolean) => {
    queryClient.setQueryData<ReportRow[]>(["reports"], (old) =>
      (old || []).map((r) => (r.id === id ? { ...r, star: !current } : r)),
    );
    const { error } = await supabase.from("reports").update({ starred: !current }).eq("id", id);
    if (error) {
      toast.error("Failed to update star");
      queryClient.invalidateQueries({ queryKey: ["reports"] });
    }
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.tagName === "INPUT") return;
      if (e.key === "/") {
        e.preventDefault();
        (document.querySelector(".hdr-search input") as HTMLInputElement | null)?.focus();
      }
      const viewKeys: Record<string, ViewKey> = { "1": "latest", "2": "sector", "3": "author", "4": "type", "5": "starred" };
      if (viewKeys[e.key]) setView(viewKeys[e.key]);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="app">
      <Header onUpload={() => setUploadOpen(true)} />
      <SubHeader view={view} />

      <div className="main">
        <Rail
          sector={sector} setSector={setSector}
          rtype={rtype} setRtype={setRtype}
          recency={recency} setRecency={setRecency}
          starred={starredOnly} setStarred={setStarredOnly}
          unread={unreadOnly} setUnread={setUnreadOnly}
        />

        <div className="content">
          <ViewSwitcher view={view} setView={setView} />
          <ColumnHead />

          {groups.map((g) => (
            <div key={g.key}>
              {g.title && (
                <div className="grp">
                  <span className="grp-title">{g.title}</span>
                  <span className="grp-count">
                    {g.items.length} {g.items.length === 1 ? "report" : "reports"}
                  </span>
                  <span className="grp-spacer" />
                  <button className="grp-action">▾ Collapse</button>
                </div>
              )}
              {g.items.map((r, i) => (
                <Row
                  key={g.key + "-" + (r.id || i)}
                  r={r}
                  onStar={() => toggleStar(r.id, r.star)}
                  onOpen={() => {
                    if (!r.id) return;
                    navigate(`/research/reports/${r.id}`);
                  }}
                  onDelete={async () => {
                    if (!window.confirm(`Delete "${r.title}"? This can't be undone.`)) return;
                    // Optimistic: remove from the cached list immediately
                    const prev = queryClient.getQueryData<ReportRow[]>(["reports"]);
                    queryClient.setQueryData<ReportRow[]>(["reports"], (xs) =>
                      (xs ?? []).filter((x) => x.id !== r.id),
                    );
                    try {
                      await deleteReport(r.id, r.file_path);
                      toast.success("Report deleted");
                      queryClient.invalidateQueries({ queryKey: ["reports"] });
                    } catch (e) {
                      queryClient.setQueryData(["reports"], prev);
                      toast.error(e instanceof Error ? e.message : "Delete failed");
                    }
                  }}
                />
              ))}
            </div>
          ))}

          {shownCount === 0 && (
            <div style={{ padding: "48px 0", textAlign: "center", color: "var(--navi-fg4)", fontSize: 13 }}>
              No reports match the current filters.
            </div>
          )}
        </div>
      </div>

      <Banner rows={rows} />

      <UploadModal
        open={uploadOpen}
        onClose={() => setUploadOpen(false)}
        onPublished={() => queryClient.invalidateQueries({ queryKey: ["reports"] })}
      />


      <div className="foot">
        <span><kbd>↑↓</kbd>navigate</span>
        <span><kbd>↵</kbd>open</span>
        <span><kbd>s</kbd>star</span>
        <span><kbd>1–5</kbd>switch view</span>
        <span><kbd>/</kbd>search</span>
        <span className="spacer" />
        <span>{shownCount} of {rows.length} reports</span>
      </div>
    </div>
  );
}
