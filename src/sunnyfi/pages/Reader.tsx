import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchReportById,
  fetchReportHtml,
  fetchTags,
  formatDate,
} from "@/sunnyfi/lib/research";
import { EditReportModal } from "@/sunnyfi/components/research/EditReportModal";
import "@/sunnyfi/research.css";

export default function Reader() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);

  // Two queries so the cache keys match what Card.tsx prefetches on hover:
  // ["report", id] for metadata and ["report-html", id] for the file body.
  const reportQ = useQuery({
    queryKey: ["report", id],
    queryFn: () => fetchReportById(id!),
    enabled: !!id,
  });
  const tagsQ = useQuery({ queryKey: ["tags"], queryFn: fetchTags });

  const report = reportQ.data ?? null;

  const htmlQ = useQuery({
    queryKey: ["report-html", id],
    queryFn: () => fetchReportHtml(report?.file_url ?? null),
    enabled: !!report?.file_url,
  });

  const html = htmlQ.data ?? null;
  const error = (reportQ.error || htmlQ.error) as Error | undefined;

  if (reportQ.isLoading) {
    return (
      <div className="ch-app reader-fade" style={{ display: "block" }}>
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
            <span className="current shimmer-text">…</span>
          </div>
          <div className="reader-skeleton-title shimmer" />
          <div className="reader-skeleton-meta shimmer" />
          <div className="reader-skeleton-iframe shimmer" />
        </main>
      </div>
    );
  }

  if (!report) {
    return (
      <div
        className="ch-app reader-fade"
        style={{ display: "block", padding: 32 }}
      >
        <p style={{ color: "var(--navi-fg2)" }}>Report not found.</p>
        <button
          className="np-btn ghost"
          onClick={() => navigate("/research")}
        >
          ← Back to Research
        </button>
      </div>
    );
  }

  return (
    <div className="ch-app reader-fade" style={{ display: "block" }}>
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
          <span className="current">{report.title}</span>
        </div>

        <div style={{ marginBottom: 24 }}>
          <div
            style={{
              display: "flex",
              alignItems: "flex-start",
              justifyContent: "space-between",
              gap: 16,
              marginBottom: 12,
            }}
          >
            <h1
              style={{
                fontSize: 36,
                fontWeight: 300,
                letterSpacing: "-1px",
                margin: 0,
                color: "var(--navi-fg1)",
              }}
            >
              {report.title}
            </h1>
            <button
              className="np-btn tinted"
              onClick={() => setEditing(true)}
              style={{ flexShrink: 0 }}
            >
              ✎ Edit
            </button>
          </div>
          <div
            style={{
              display: "flex",
              gap: 6,
              flexWrap: "wrap",
              alignItems: "center",
              marginBottom: 12,
            }}
          >
            <span className="ch-card-date-inline">
              {formatDate(report.created_at)}
            </span>
            {report.tags.map((t) => (
              <button
                key={t}
                type="button"
                className="ch-tag-pill"
                onClick={() =>
                  navigate(`/research/tags/${encodeURIComponent(t)}`)
                }
                style={{ cursor: "pointer" }}
              >
                #{t}
              </button>
            ))}
          </div>
          {report.description && (
            <p
              style={{
                color: "var(--navi-fg2)",
                fontSize: 15,
                lineHeight: 1.55,
                maxWidth: 720,
              }}
            >
              {report.description}
            </p>
          )}
        </div>

        {error && (
          <div
            style={{
              background: "var(--navi-tint-negative)",
              color: "var(--navi-negative)",
              padding: 12,
              borderRadius: 8,
              fontSize: 13,
              marginBottom: 16,
            }}
          >
            Couldn't load file: {error.message}
          </div>
        )}

        {html ? (
          <iframe
            key={report.id}
            title={report.title}
            srcDoc={html}
            sandbox="allow-scripts allow-popups allow-popups-to-escape-sandbox"
            className="reader-iframe-fade"
            style={{
              width: "100%",
              minHeight: "70vh",
              border: "1px solid var(--navi-elevated)",
              borderRadius: 12,
              background: "#fff",
            }}
          />
        ) : report.file_url ? (
          <div className="reader-skeleton-iframe shimmer" />
        ) : (
          <p style={{ color: "var(--navi-fg3)", fontSize: 13 }}>
            No file attached.
          </p>
        )}
      </main>

      <EditReportModal
        open={editing}
        onClose={() => setEditing(false)}
        report={report}
        knownTags={(tagsQ.data ?? []).map((t) => t.name)}
        onSaved={(updated) => {
          // Update both the single-report cache and the list cache so the
          // reader, the rail, and any open list views all reflect the edit
          // immediately — no refetch round-trip needed.
          qc.setQueryData(["report", report.id], updated);
          qc.invalidateQueries({ queryKey: ["reports"] });
          qc.invalidateQueries({ queryKey: ["tags"] });
        }}
      />
    </div>
  );
}
