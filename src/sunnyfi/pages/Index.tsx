import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { fetchReports, fetchTags, type Report, type Tag } from "@/sunnyfi/lib/research";
import { Card } from "@/sunnyfi/components/research/Card";
import { TagRail } from "@/sunnyfi/components/research/TagRail";
import { UploadModal } from "@/sunnyfi/components/research/UploadModal";
import { SearchModal } from "@/sunnyfi/components/research/SearchModal";
import "@/sunnyfi/research.css";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

export default function Index() {
  const navigate = useNavigate();
  const [showUpload, setShowUpload] = useState(false);
  const [showSearch, setShowSearch] = useState(false);

  const reportsQ = useQuery({ queryKey: ["reports"], queryFn: fetchReports });
  const tagsQ = useQuery({ queryKey: ["tags"], queryFn: fetchTags });

  const reports = reportsQ.data ?? [];
  const tags = tagsQ.data ?? [];

  // Bands: one per pinned tag, anchored by the most recent report.
  const pinnedTags = useMemo(
    () => tags.filter((t) => t.pinned).slice(0, 3),
    [tags],
  );

  const latest = useMemo(() => reports.slice(0, 6), [reports]);

  const onPick = (t: string) =>
    navigate(`/research/tags/${encodeURIComponent(t)}`);

  return (
    <>
      <ResearchTopBar
        onUpload={() => setShowUpload(true)}
        onSearch={() => setShowSearch(true)}
      />

      <div className="ch-app">
        <TagRail tags={tags} />

        <main className="ch-main">
          <header className="ch-page-head">
            <h1 className="ch-page-title">Research</h1>
            <div className="ch-page-meta">
              <span className="np-pill">
                <span className="dot" />
                {reports.length} report{reports.length === 1 ? "" : "s"}
                {reports.length > 0 && ` · ${countThisWeek(reports)} this week`}
              </span>
            </div>
          </header>

          {reportsQ.isLoading ? (
            <p style={{ color: "var(--navi-fg3)", fontSize: 13 }}>Loading…</p>
          ) : reports.length === 0 ? (
            <EmptyState onUpload={() => setShowUpload(true)} />
          ) : (
            <>
              {pinnedTags.map((t, i) => (
                <PinnedBand
                  key={t.name}
                  tag={t}
                  reports={reports.filter((r) => r.tags.includes(t.name))}
                  layout={i === 0 ? "band-1" : "band-2"}
                  onPick={onPick}
                />
              ))}

              <section className="ch-band">
                <div className="ch-band-head">
                  <span className="ch-band-tag" style={{ cursor: "default" }}>
                    Latest
                  </span>
                  <span className="ch-band-meta">
                    EVERYTHING · NEWEST FIRST
                  </span>
                </div>
                <div className="ch-band-3">
                  {latest.map((r) => (
                    <Card key={r.id} r={r} />
                  ))}
                </div>
              </section>
            </>
          )}
        </main>
      </div>

      <UploadModal
        open={showUpload}
        onClose={() => setShowUpload(false)}
        onCreated={() => {
          reportsQ.refetch();
          tagsQ.refetch();
        }}
        knownTags={tags.map((t) => t.name)}
      />
      <SearchModal
        open={showSearch}
        onClose={() => setShowSearch(false)}
        reports={reports}
        tags={tags}
      />
    </>
  );
}

function PinnedBand({
  tag,
  reports,
  layout,
  onPick,
}: {
  tag: Tag;
  reports: Report[];
  layout: "band-1" | "band-2";
  onPick: (t: string) => void;
}) {
  if (reports.length === 0) return null;
  // band-1 wants 4 cards (xl, m, s, s). band-2 wants 5 (l, m, m, s, s).
  return (
    <section className="ch-band">
      <div className="ch-band-head">
        <button
          type="button"
          className="ch-band-tag"
          onClick={() => onPick(tag.name)}
        >
          <span className="hash">#</span>
          {tag.name}
        </button>
        <span className="ch-band-pinned-badge">PINNED</span>
        <span className="ch-band-meta">{tag.count} reports</span>
        <button
          type="button"
          className="ch-band-link"
          onClick={() => onPick(tag.name)}
        >
          view all →
        </button>
      </div>
      <div className={`ch-${layout}`}>
        {layout === "band-1"
          ? reports
              .slice(0, 4)
              .map((r, i) => (
                <Card
                  key={r.id}
                  r={r}
                  primaryTag={tag.name}
                  size={i === 0 ? "xl" : i === 1 ? "m" : "s"}
                />
              ))
          : reports
              .slice(0, 5)
              .map((r, i) => (
                <Card
                  key={r.id}
                  r={r}
                  primaryTag={tag.name}
                  size={i === 0 ? "l" : i < 3 ? "m" : "s"}
                />
              ))}
      </div>
    </section>
  );
}

function ResearchTopBar({
  onUpload,
  onSearch,
}: {
  onUpload: () => void;
  onSearch: () => void;
}) {
  return (
    <header className="np-top">
      <div className="np-brand-row">
        <a className="np-brand" href={DASHBOARD_URL} title="Back to dashboard">
          Sunnyfi<span className="cursor" />
        </a>
        <span className="np-crumb-sep">/</span>
        <span className="np-crumb">RESEARCH</span>
      </div>
      <div className="np-actions">
        <button className="np-btn ghost" onClick={onSearch}>
          ⌕ Search
        </button>
        <button className="np-btn neon" onClick={onUpload}>
          ↑ Upload report
        </button>
      </div>
    </header>
  );
}

function EmptyState({ onUpload }: { onUpload: () => void }) {
  return (
    <div
      style={{
        padding: "64px 32px",
        textAlign: "center",
        border: "1px dashed var(--navi-elevated)",
        borderRadius: 12,
      }}
    >
      <p
        style={{
          color: "var(--navi-fg2)",
          fontSize: 14,
          marginBottom: 16,
        }}
      >
        No reports yet — upload your first one.
      </p>
      <button className="np-btn neon" onClick={onUpload}>
        ↑ Upload report
      </button>
    </div>
  );
}

function countThisWeek(reports: Report[]): number {
  const cutoff = Date.now() - 7 * 86_400_000;
  return reports.filter((r) => new Date(r.created_at).getTime() > cutoff).length;
}
