// The brief's rich text: runs of { t, b, c } (BriefSpan on the phone). Bold runs at the phone's bold (700 in the
// lede), a run's colour from its role; privacy masks every book dollar. Headlines read thick then thin: the first
// sentence in the headline weight, the rest regular (the phone's HeadlineWeight.split).
import type { CSSProperties } from 'react';
import type { J } from '../../lib/data';
import { clean, named } from '../../lib/format';

export interface Span { t: string; b?: boolean; c?: string }

export function spansOf(v: J): Span[] {
  if (typeof v === 'string') return [{ t: v }];
  if (!Array.isArray(v)) return [];
  return v.map((x: J) => (typeof x === 'string' ? { t: x } : x && typeof x.t === 'string' ? { t: x.t, b: !!x.b, c: x.c ?? undefined } : null))
    .filter(Boolean) as Span[];
}

const runColor = (c?: string) => (c ? named(c, 'inherit') : undefined);

/** A list of runs as inline spans. */
export function Runs({ spans, mask, bold = 700 }: { spans: Span[]; mask: (s: string) => string; bold?: number }) {
  return (
    <>
      {spans.map((s, i) => {
        const st: CSSProperties = {};
        if (s.b) st.fontWeight = bold;
        const col = runColor(s.c);
        if (col) st.color = col;
        return <span key={i} style={st}>{mask(clean(s.t))}</span>;
      })}
    </>
  );
}

const ABBR = new Set(['mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr', 'inc', 'corp', 'co', 'ltd', 'vs', 'approx', 'no', 'jan', 'feb', 'mar', 'apr',
  'jun', 'jul', 'aug', 'sep', 'sept', 'oct', 'nov', 'dec', 'mon', 'tue', 'tues', 'wed', 'thu', 'thur', 'thurs', 'fri', 'sat', 'sun']);

/** Just past the space after the first sentence, or null when the text is one sentence (HeadlineWeight). */
function firstSentenceEnd(c: string[]): number | null {
  for (let i = 0; i < c.length - 1; i++) {
    if (!'.!?'.includes(c[i])) continue;
    let j = i + 1;
    while (j < c.length && '”’")\''.includes(c[j])) j++;
    if (!(j < c.length && c[j] === ' ' && c.slice(j + 1).some((x) => !/\s/.test(x)))) continue;
    if (c[i] === '.') {
      let k = i;
      while (k > 0 && !/\s/.test(c[k - 1])) k--;
      const word = c.slice(k, i).join('').replace(/^[(“"]+|[(“"]+$/g, '');
      if (ABBR.has(word.toLowerCase())) continue;
      // Initials and dotted short forms: "U.S.", "a.m.", "e.g.", a single capital ("J. Powell"); an ellipsis.
      if (/^([A-Za-z]\.)+[A-Za-z]$/.test(word)) continue;
      if (word.length === 1 && /[A-Z]/.test(word)) continue;
      if (i > 0 && c[i - 1] === '.') continue;
    }
    return j + 1;
  }
  return null;
}

/** Thick then thin: { thick, thin } runs. */
export function splitHeadline(spans: Span[]): { thick: Span[]; thin: Span[] } {
  const chars = Array.from(spans.map((s) => s.t).join(''));
  const cut = firstSentenceEnd(chars) ?? chars.length;
  const thick: Span[] = [], thin: Span[] = [];
  let at = 0;
  for (const r of spans) {
    const cs = Array.from(r.t), end = at + cs.length;
    if (end <= cut) thick.push(r);
    else if (at >= cut) thin.push(r);
    else { const k = cut - at; thick.push({ ...r, t: cs.slice(0, k).join('') }); thin.push({ ...r, t: cs.slice(k).join('') }); }
    at = end;
  }
  // The space between the two halves is drawn by the layout.
  if (thick.length) thick[thick.length - 1] = { ...thick[thick.length - 1], t: thick[thick.length - 1].t.replace(/\s+$/, '') };
  return { thick, thin };
}
