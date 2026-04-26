import { useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import type { Tag, TagGroup } from "@/sunnyfi/lib/research";

interface Props {
  tags: Tag[];
}

export function TagRail({ tags }: Props) {
  const { tag: activeTag } = useParams<{ tag?: string }>();
  const navigate = useNavigate();
  const [search, setSearch] = useState("");

  const groups = useMemo(() => {
    const filtered = search
      ? tags.filter((t) =>
          t.name.toLowerCase().includes(search.toLowerCase()),
        )
      : tags;
    const by: Record<TagGroup, Tag[]> = {
      pinned: [],
      tickers: [],
      themes: [],
      custom: [],
    };
    for (const t of filtered) by[t.group].push(t);
    // Sort each group by count desc then name.
    for (const k of Object.keys(by) as TagGroup[]) {
      by[k].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
    }
    return by;
  }, [tags, search]);

  return (
    <aside className="ch-rail">
      <input
        className="ch-rail-search"
        placeholder="⌕ search tags…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />

      {(["pinned", "tickers", "themes", "custom"] as TagGroup[]).map((g) => {
        const items = groups[g];
        if (items.length === 0) return null;
        return (
          <div key={g} className="ch-rail-group">
            <div className="ch-rail-head">{g}</div>
            {items.map((t) => (
              <button
                key={t.name}
                type="button"
                className={
                  "ch-tag-row" +
                  (g === "pinned" ? " pinned" : "") +
                  (activeTag && decodeURIComponent(activeTag) === t.name
                    ? " active"
                    : "")
                }
                onClick={() =>
                  navigate(`/research/tags/${encodeURIComponent(t.name)}`)
                }
              >
                {g === "pinned" && <span className="ch-pin-dot" />}
                <span className="ch-tag-name">#{t.name}</span>
                <span className="ch-tag-count">{t.count}</span>
              </button>
            ))}
          </div>
        );
      })}
    </aside>
  );
}
