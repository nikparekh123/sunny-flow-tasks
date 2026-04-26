import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { toast } from "sonner";
import {
  fetchReportById,
  fetchReportHtml,
  formatDate,
  type Report,
} from "@/sunnyfi/lib/research";
import "@/sunnyfi/research.css";

export default function Reader() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [report, setReport] = useState<Report | null>(null);
  const [html, setHtml] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const r = await fetchReportById(id);
        if (cancelled) return;
        setReport(r);
        if (r?.file_url) {
          const text = await fetchReportHtml(r.file_url);
          if (cancelled) return;
          setHtml(text);
        }
      } catch (e) {
        if (!cancelled) setError((e as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  if (loading && !report) {
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
      <div className="ch-app reader-fade" style={{ display: "block", padding: 32 }}>
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
          <h1
            style={{
              fontSize: 36,
              fontWeight: 300,
              letterSpacing: "-1px",
              margin: "0 0 12px",
              color: "var(--navi-fg1)",
            }}
          >
            {report.title}
          </h1>
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
            Couldn't load file: {error}
          </div>
        )}

        {html ? (
          <iframe
            key={report.id}
            title={report.title}
            srcDoc={html}
            sandbox="allow-same-origin"
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
    </div>
  );
}
