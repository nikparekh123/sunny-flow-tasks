import { useNavigate } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import {
  type Report,
  type CardSize,
  deriveSize,
  formatDate,
  fetchReportHtml,
} from "@/sunnyfi/lib/research";

interface Props {
  r: Report;
  /** When set, this tag's pill renders in the neon "primary" style. */
  primaryTag?: string;
  /** Override the auto-derived size. */
  size?: CardSize;
}

export function Card({ r, primaryTag, size: sizeOverride }: Props) {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const size = sizeOverride ?? deriveSize(r);
  const maxTags = size === "s" ? 2 : 4;

  // Prefetch on hover so by the time the user clicks, both the report
  // metadata and the file body are warm in React Query's cache. Reader
  // reads from the same query keys.
  const prefetch = () => {
    qc.setQueryData(["report", r.id], r);
    if (r.file_url) {
      qc.prefetchQuery({
        queryKey: ["report-html", r.id],
        queryFn: () => fetchReportHtml(r.file_url),
        // 5 minutes — long enough that the prefetch isn't wasted if the
        // user ponders before clicking.
        staleTime: 5 * 60_000,
      });
    }
  };

  const onClick = () => navigate(`/research/reports/${r.id}`);
  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      onClick();
    }
  };

  return (
    <button
      className={`ch-card size-${size} ${r.featured ? "featured" : ""}`}
      onClick={onClick}
      onKeyDown={onKey}
      onMouseEnter={prefetch}
      onFocus={prefetch}
      type="button"
    >
      {r.pinned && (
        <div className="ch-card-pin">
          <span className="dot" /> PINNED
        </div>
      )}
      <h3 className="ch-card-title">{r.title}</h3>
      {r.description && size !== "s" && (
        <p className="ch-card-desc">{r.description}</p>
      )}
      <div className="ch-card-tags">
        <span className="ch-card-date-inline">{formatDate(r.created_at)}</span>
        {r.tags.slice(0, maxTags).map((t) => (
          <span
            key={t}
            className={`ch-tag-pill ${t === primaryTag ? "primary" : ""}`}
          >
            #{t}
          </span>
        ))}
      </div>
    </button>
  );
}
