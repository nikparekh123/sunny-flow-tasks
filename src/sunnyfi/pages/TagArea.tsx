import { useMemo, useState, useEffect } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  fetchReports,
  fetchTags,
  fetchRelatedTags,
  setTagPinned,
  setTagDescription,
  type Report,
} from "@/sunnyfi/lib/research";
import { Card } from "@/sunnyfi/components/research/Card";
import { TagRail } from "@/sunnyfi/components/research/TagRail";
import { UploadModal } from "@/sunnyfi/components/research/UploadModal";
import { SearchModal } from "@/sunnyfi/components/research/SearchModal";
import "@/sunnyfi/research.css";

const DASHBOARD_URL = "https://www.sunnyfi.co/dashboard";

type Filter = "all" | "starred" | "quarter" | "year";

export default function TagArea() {
  const { tag: tagParam } = useParams<{ tag: string }>();
  const tag = tagParam ? decodeURIComponent(tagParam) : "";
  const navigate = useNavigate();
  const [filter, setFilter] = useState<Filter>("all");
  const [editing, setEditing] = useState(false);
  const [draftDesc, setDraftDesc] = useState("");
  const [showUpload, setShowUpload] = useState(false);
  const [showSearch, setShowSearch] = useState(false);

  const reportsQ = useQuery({ queryKey: ["reports"], queryFn: fetchReports });
  const tagsQ = useQuery({ queryKey: ["tags"], queryFn: fetchTags });
  const relatedQ = useQuery({
    queryKey: ["related", tag],
    queryFn: () => fetchRelatedTags(tag, 8),
    enabled: !!tag,
  });

  const allReports = reportsQ.data ?? [];
  const allTags = tagsQ.data ?? [];
  const tagMeta = useMemo(
    () => allTags.find((t) => t.name === tag),
    [allTags, tag],
  );

  // Reset edit-mode draft whenever the tag's description is reloaded.
  useEffect(() => {
    setDraftDesc(tagMeta?.description ?? "");
  }, [tagMeta?.description]);

  const tagReports = useMemo(
    () => allReports.filter((r) => r.tags.includes(tag)),
    [allReports, tag],
  );

  const filtered = useMemo(() => {
    const cutoffQuarter = Date.now() - 90 * 86_400_000;
    const cutoffYear = Date.now() - 365 * 86_400_000;
    if (filter === "starred") return tagReports.filter((r) => r.starred);
    if (filter === "quarter")
      return tagReports.filter(
        (r) => new Date(r.created_at).getTime() > cutoffQuarter,
      );
    if (filter === "year")
      return tagReports.filter(
        (r) => new Date(r.created_at).getTime() > cutoffYear,
      );
    return tagReports;
  }, [tagReports, filter]);

  const counts = useMemo(() => {
    const cutoffQuarter = Date.now() - 90 * 86_400_000;
    const cutoffYear = Date.now() - 365 * 86_400_000;
    return {
      all: tagReports.length,
      starred: tagReports.filter((r) => r.starred).length,
      quarter: tagReports.filter(
        (r) => new Date(r.created_at).getTime() > cutoffQuarter,
      ).length,
      year: tagReports.filter(
        (r) => new Date(r.created_at).getTime() > cutoffYear,
      ).length,
    };
  }, [tagReports]);

  const lastUpdated = tagReports[0]?.created_at;
  const starredCount = counts.starred;

  const togglePin = async () => {
    try {
      await setTagPinned(tag, !(tagMeta?.pinned ?? false));
      tagsQ.refetch();
      toast.success(tagMeta?.pinned ? "Unpinned." : "Pinned to home.");
    } catch (e) {
      toast.error((e as Error).message);
    }
  };

  const saveDesc = async () => {
    try {
      await setTagDescription(tag, draftDesc.trim() || null);
      tagsQ.refetch();
      setEditing(false);
      toast.success("Description saved.");
    } catch (e) {
      toast.error((e as Error).message);
    }
  };

  return (
    <>
      <ResearchTopBar
        onUpload={() => setShowUpload(true)}
        onSearch={() => setShowSearch(true)}
      />

      <div className="ch-app">
        <TagRail tags={allTags} />

        <main className="ch-main">
          <div className="ch-breadcrumb">
            <button
              type="button"
              className="crumb"
              onClick={() => navigate("/research")}
            >
              Research
            </button>
            {" / "}
            <span className="crumb">Tags</span>
            {" / "}
            <span className="current">#{tag}</span>
          </div>

          <div className="ch-tag-hero">
            <div className="ch-tag-hero-main">
              <div className="ch-tag-hero-name">
                <span className="hash">#</span>
                {tag}
              </div>
              <div className="ch-tag-hero-stat">
                <span className="neon">
                  {tagReports.length} report
                  {tagReports.length === 1 ? "" : "s"}
                </span>
                {tagMeta?.pinned && " · pinned"}
                {lastUpdated &&
                  ` · last updated ${formatStatDate(lastUpdated)}`}
                {starredCount > 0 && ` · ${starredCount} starred`}
              </div>

              {editing ? (
                <textarea
                  className="ch-tag-hero-desc"
                  value={draftDesc}
                  onChange={(e) => setDraftDesc(e.target.value)}
                  autoFocus
                  onBlur={saveDesc}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") {
                      setDraftDesc(tagMeta?.description ?? "");
                      setEditing(false);
                    }
                    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) saveDesc();
                  }}
                />
              ) : (
                <p
                  className="ch-tag-hero-desc"
                  style={{ cursor: "text" }}
                  onClick={() => setEditing(true)}
                >
                  {tagMeta?.description ||
                    "Click to add a description for this tag."}
                </p>
              )}

              {(relatedQ.data?.length ?? 0) > 0 && (
                <>
                  <div className="ch-tag-related-label">
                    OFTEN APPEARS WITH
                  </div>
                  <div className="ch-tag-related">
                    {relatedQ.data?.map((r) => (
                      <button
                        key={r.name}
                        type="button"
                        className="ch-tag-pill"
                        onClick={() =>
                          navigate(
                            `/research/tags/${encodeURIComponent(r.name)}`,
                          )
                        }
                        style={{ cursor: "pointer" }}
                      >
                        #{r.name}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>
            <div className="ch-tag-hero-actions">
              <button className="np-btn neon" onClick={togglePin}>
                📌 {tagMeta?.pinned ? "Unpin" : "Pin"}
              </button>
              <button
                className="np-btn tinted"
                onClick={() => setEditing(true)}
              >
                Edit description
              </button>
            </div>
          </div>

          <div className="ch-subfilter">
            <button
              className={`ch-chip ${filter === "all" ? "on" : ""}`}
              onClick={() => setFilter("all")}
            >
              all {counts.all}
            </button>
            <button
              className={`ch-chip ${filter === "starred" ? "on" : ""}`}
              onClick={() => setFilter("starred")}
            >
              starred {counts.starred}
            </button>
            <button
              className={`ch-chip ${filter === "quarter" ? "on" : ""}`}
              onClick={() => setFilter("quarter")}
            >
              this quarter {counts.quarter}
            </button>
            <button
              className={`ch-chip ${filter === "year" ? "on" : ""}`}
              onClick={() => setFilter("year")}
            >
              this year {counts.year}
            </button>
            <span className="ch-spacer" />
            <button className="ch-chip">sort: recent ↓</button>
          </div>

          {filtered.length === 0 ? (
            <p style={{ color: "var(--navi-fg3)", fontSize: 13 }}>
              {tagReports.length === 0
                ? `No reports tagged #${tag} yet.`
                : "No reports match this filter."}
            </p>
          ) : (
            <div className="ch-mosaic">
              {filtered.map((r) => (
                <Card key={r.id} r={r} primaryTag={tag} />
              ))}
            </div>
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
        knownTags={allTags.map((t) => t.name)}
      />
      <SearchModal
        open={showSearch}
        onClose={() => setShowSearch(false)}
        reports={allReports}
        tags={allTags}
      />
    </>
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

function formatStatDate(iso: string): string {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  return d.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}
