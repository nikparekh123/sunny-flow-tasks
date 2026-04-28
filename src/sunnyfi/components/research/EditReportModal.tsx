import { useEffect, useState } from "react";
import { toast } from "sonner";
import { updateReport, type Report } from "@/sunnyfi/lib/research";

interface Props {
  open: boolean;
  onClose: () => void;
  report: Report;
  onSaved?: (r: Report) => void;
  knownTags: string[];
}

const MAX_DESC = 220;

export function EditReportModal({
  open,
  onClose,
  report,
  onSaved,
  knownTags,
}: Props) {
  const [title, setTitle] = useState(report.title);
  const [desc, setDesc] = useState(report.description ?? "");
  const [tags, setTags] = useState<string[]>(report.tags);
  const [tagInput, setTagInput] = useState("");
  const [pin, setPin] = useState(report.pinned);
  const [feat, setFeat] = useState(report.featured);
  const [saving, setSaving] = useState(false);

  // Re-seed when the modal opens or the report changes.
  useEffect(() => {
    if (open) {
      setTitle(report.title);
      setDesc(report.description ?? "");
      setTags(report.tags);
      setTagInput("");
      setPin(report.pinned);
      setFeat(report.featured);
      setSaving(false);
    }
  }, [open, report]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !saving) onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, saving, onClose]);

  if (!open) return null;

  const addTag = (raw?: string) => {
    const v = (raw ?? tagInput).trim().replace(/^#/, "");
    if (v && !tags.includes(v)) setTags([...tags, v]);
    setTagInput("");
  };
  const removeTag = (t: string) => setTags(tags.filter((x) => x !== t));
  const onTagKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter" || e.key === ",") {
      e.preventDefault();
      addTag();
    }
    if (e.key === "Backspace" && !tagInput && tags.length) {
      removeTag(tags[tags.length - 1]);
    }
  };

  const newTags = tags.filter((t) => !knownTags.includes(t));

  const handleSave = async () => {
    if (!title.trim() || tags.length === 0) return;
    setSaving(true);
    try {
      const updated = await updateReport(report.id, {
        title: title.trim(),
        description: desc.trim() || null,
        tags,
        featured: feat,
        pinned: pin,
      });
      toast.success("Report updated.");
      onSaved?.(updated);
      onClose();
    } catch (e) {
      toast.error(`Update failed: ${(e as Error).message}`);
      setSaving(false);
    }
  };

  return (
    <div
      className="np-modal-back"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="np-modal"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 580 }}
      >
        <div className="np-modal-hd">
          <div>
            <div className="np-modal-title">Edit report</div>
            <div className="np-modal-sub">change title, description, tags</div>
          </div>
          <button
            className="np-btn ghost"
            onClick={onClose}
            disabled={saving}
            style={{ fontSize: 18, padding: "4px 10px" }}
          >
            ×
          </button>
        </div>

        <div className="ch-modal-body">
          <div className="ch-field">
            <label className="ch-field-label">Title</label>
            <input
              className="ch-field-input"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="e.g. Netflix ad-tier inflection"
            />
          </div>

          <div className="ch-field">
            <label className="ch-field-label">Description</label>
            <textarea
              className="ch-field-textarea"
              value={desc}
              onChange={(e) => setDesc(e.target.value.slice(0, MAX_DESC))}
              placeholder="2 sentences max — shows on the card"
              maxLength={MAX_DESC}
            />
            <div className="ch-char-count">
              {desc.length}/{MAX_DESC}
            </div>
          </div>

          <div className="ch-field">
            <label className="ch-field-label">Tags</label>
            <div className="ch-tag-input">
              {tags.map((t) => (
                <span key={t} className="ch-tag-chip">
                  #{t}
                  <button
                    type="button"
                    className="x"
                    onClick={() => removeTag(t)}
                    aria-label={`Remove ${t}`}
                  >
                    ×
                  </button>
                </span>
              ))}
              <input
                className="ch-tag-input-field"
                value={tagInput}
                onChange={(e) => setTagInput(e.target.value)}
                onKeyDown={onTagKey}
                placeholder={tags.length ? "add tag…" : "NFLX, streaming, ads"}
              />
            </div>
            {newTags.length > 0 && (
              <div className="ch-newtag-hint">
                ✦ NEW TAG <b>#{newTags[0]}</b> WILL CREATE THE AREA PAGE{" "}
                <span className="path">
                  → /research/tags/{encodeURIComponent(newTags[0])}
                </span>
              </div>
            )}
          </div>

          <div className="ch-checkrow">
            <label>
              <input
                type="checkbox"
                checked={pin}
                onChange={(e) => setPin(e.target.checked)}
              />
              Pin to home
            </label>
            <label>
              <input
                type="checkbox"
                checked={feat}
                onChange={(e) => setFeat(e.target.checked)}
              />
              Feature (XL card)
            </label>
          </div>

          <div className="ch-modal-foot">
            <div className="ch-modal-hint">
              changes apply immediately
            </div>
            <div className="ch-modal-actions">
              <button
                className="np-btn ghost"
                onClick={onClose}
                disabled={saving}
              >
                Cancel
              </button>
              <button
                className="np-btn neon"
                onClick={handleSave}
                disabled={!title.trim() || tags.length === 0 || saving}
              >
                {saving ? "Saving…" : "Save changes"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
