import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { createReport } from "@/sunnyfi/lib/research";

interface Props {
  open: boolean;
  onClose: () => void;
  onCreated?: () => void;
  /** Tags already in the system, used for "new tag" hint and suggestions. */
  knownTags: string[];
  /** Pre-filled tag suggestions (top co-occurring or user history). */
  suggested?: string[];
}

const MAX_DESC = 220;

export function UploadModal({
  open,
  onClose,
  onCreated,
  knownTags,
  suggested = ["content", "MRQ", "longs", "shorts"],
}: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [drag, setDrag] = useState(false);
  const [title, setTitle] = useState("");
  const [desc, setDesc] = useState("");
  const [tags, setTags] = useState<string[]>([]);
  const [tagInput, setTagInput] = useState("");
  const [pin, setPin] = useState(false);
  const [feat, setFeat] = useState(false);
  const [saving, setSaving] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  // Reset on close.
  useEffect(() => {
    if (!open) {
      setFile(null);
      setTitle("");
      setDesc("");
      setTags([]);
      setTagInput("");
      setPin(false);
      setFeat(false);
      setSaving(false);
    }
  }, [open]);

  // Esc to close.
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

  const onDropFile = (e: React.DragEvent) => {
    e.preventDefault();
    setDrag(false);
    const f = e.dataTransfer.files[0];
    if (f) setFile(f);
  };

  const handlePublish = async () => {
    if (!title.trim() || tags.length === 0) return;
    setSaving(true);
    try {
      await createReport({
        title: title.trim(),
        description: desc.trim(),
        tags,
        featured: feat,
        pinned: pin,
        file: file ?? undefined,
      });
      toast.success("Report published.");
      onCreated?.();
      onClose();
    } catch (e) {
      toast.error(`Publish failed: ${(e as Error).message}`);
      setSaving(false);
    }
  };

  return (
    <div
      className="np-modal-back"
      onClick={(e) => {
        if (
          e.target === e.currentTarget &&
          (e.target as HTMLElement).classList.contains("np-modal-back")
        )
          onClose();
      }}
    >
      <div
        className="np-modal"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 580 }}
      >
        <div className="np-modal-hd">
          <div>
            <div className="np-modal-title">Upload report</div>
            <div className="np-modal-sub">add to research library</div>
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
          <input
            ref={fileInputRef}
            type="file"
            accept=".html,.htm,.pdf,.docx,.md,.txt,text/html,application/pdf"
            style={{ display: "none" }}
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) setFile(f);
            }}
          />

          {!file ? (
            <div
              className={`ch-drop ${drag ? "dragover" : ""}`}
              onClick={() => fileInputRef.current?.click()}
              onDragOver={(e) => {
                e.preventDefault();
                setDrag(true);
              }}
              onDragLeave={() => setDrag(false)}
              onDrop={onDropFile}
            >
              <div className="ch-drop-title">
                Drop file here or click to browse
              </div>
              <div className="ch-drop-sub">HTML · PDF · DOCX · MD · TXT</div>
            </div>
          ) : (
            <div className="ch-drop has-file">
              <div className="file-icon" />
              <div>
                <div className="file-name">{file.name}</div>
                <div className="file-sub">
                  {(file.size / 1024).toFixed(0)} KB
                </div>
              </div>
              <button
                className="ch-drop-clear"
                onClick={() => setFile(null)}
                aria-label="Clear file"
              >
                ×
              </button>
            </div>
          )}

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
            <div className="ch-suggested">
              <span className="ch-suggested-label">SUGGESTED</span>
              {suggested
                .filter((s) => !tags.includes(s))
                .slice(0, 6)
                .map((s) => (
                  <button
                    key={s}
                    type="button"
                    className="ch-suggested-pill"
                    onClick={() => addTag(s)}
                  >
                    #{s}
                  </button>
                ))}
            </div>
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
              {tags[0] ? (
                <>
                  preview shows on{" "}
                  <span className="neon">#{tags[0]}</span> page
                </>
              ) : (
                "add at least one tag to publish"
              )}
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
                onClick={handlePublish}
                disabled={!title.trim() || tags.length === 0 || saving}
              >
                {saving ? "Publishing…" : "Publish"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
