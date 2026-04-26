import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { Report, Tag } from "@/sunnyfi/lib/research";
import { formatDate } from "@/sunnyfi/lib/research";

interface Props {
  open: boolean;
  onClose: () => void;
  reports: Report[];
  tags: Tag[];
}

export function SearchModal({ open, onClose, reports, tags }: Props) {
  const [q, setQ] = useState("");
  const inputRef = useRef<HTMLInputElement | null>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (open) {
      setQ("");
      // Focus on next tick.
      setTimeout(() => inputRef.current?.focus(), 0);
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  const ql = q.trim().toLowerCase();
  const tagHits = ql
    ? tags.filter((t) => t.name.toLowerCase().includes(ql)).slice(0, 6)
    : tags.slice(0, 6);
  const reportHits = ql
    ? reports
        .filter(
          (r) =>
            r.title.toLowerCase().includes(ql) ||
            (r.description ?? "").toLowerCase().includes(ql) ||
            r.tags.some((t) => t.toLowerCase().includes(ql)),
        )
        .slice(0, 6)
    : reports.slice(0, 5);

  const goToTag = (name: string) => {
    onClose();
    navigate(`/research/tags/${encodeURIComponent(name)}`);
  };
  const goToReport = (id: string) => {
    onClose();
    navigate(`/research/reports/${id}`);
  };

  return (
    <div
      className="np-modal-back"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="np-modal ch-search-modal"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="ch-search-input-wrap">
          <span className="ch-search-icon">⌕</span>
          <input
            ref={inputRef}
            className="ch-search-input"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search reports, tags, descriptions…"
          />
          <span className="ch-search-kbd">ESC</span>
        </div>

        <div className="ch-search-body">
          <div className="ch-search-section-head">
            {ql ? "TAG MATCHES" : "JUMP TO TAG"}
          </div>
          {tagHits.length === 0 && (
            <div className="ch-search-empty">no tags match</div>
          )}
          {tagHits.map((t) => (
            <button
              key={t.name}
              type="button"
              className="ch-search-row"
              onClick={() => goToTag(t.name)}
            >
              <span className="ch-search-row-tag">#{t.name}</span>
              <span className="ch-search-row-meta">
                {t.group.toUpperCase()}
              </span>
              <span className="ch-search-row-count">{t.count} reports</span>
            </button>
          ))}

          <div
            className="ch-search-section-head"
            style={{ marginTop: 18 }}
          >
            {ql ? "REPORT MATCHES" : "RECENT REPORTS"}
          </div>
          {reportHits.length === 0 && (
            <div className="ch-search-empty">no reports match</div>
          )}
          {reportHits.map((r) => (
            <button
              key={r.id}
              type="button"
              className="ch-search-row"
              onClick={() => goToReport(r.id)}
            >
              <span className="ch-search-row-title">{r.title}</span>
              <span className="ch-search-row-tags">
                {r.tags.slice(0, 3).map((t) => (
                  <span key={t} className="ch-tag-pill">
                    #{t}
                  </span>
                ))}
              </span>
              <span className="ch-search-row-date">
                {formatDate(r.created_at)}
              </span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
