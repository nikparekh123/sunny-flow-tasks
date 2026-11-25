// Your book (Nik, 24 Nov 2026: "No need for Today and All time, just all time"): each leg, not Long, Hedge and Income.
// Header: Your book, and on the right how many tickers and legs. Then one block per part the book holds, in this
// order: Shares, Calls bought, Calls sold, Puts bought, Puts sold, in a grid that fills the width on a wide screen and
// is one column on a phone. Each block (Nik, 25 Nov 2026: "Now (change %), on tap change dollars, TV", one line):
//   The part's name, muted.
//   What it is worth now big in ink (sold: what it costs to buy back), then the all-time change in brackets, green
//   gained or kept, red lost, never a minus sign: the % (on cost; sold: the share of what was collected) or, after a
//   click on any block, the dollars. Options end the line with a clock and their time value.
// The picked name's own book follows in the same blocks, only the parts it holds.
// Every figure is sunny-home's (payload.brief_inputs.parts, totals.ts), the same numbers the phone reads.

import { useState } from 'react';

/** A whole-number percent, no sign (Nik, 25 Nov 2026: "Use no decimal in %"). */
const pct = (x: number) => `${Math.round(Math.abs(x))}%`;
/** Whole K and M, no decimals, no sign (Nik, 25 Nov 2026: "Round off the numbers also to be K M no decimals"). */
const money0 = (v: number) => {
  const a = Math.abs(v);
  return a >= 999_500 ? `$${Math.round(a / 1e6)}M` : a >= 999.5 ? `$${Math.round(a / 1e3)}K` : `$${Math.round(a)}`;
};
import { PARTS, legsIn, type PKey, type Part, type Parts } from './totals';
import { G, K, MU, R } from './ui';

const RULE = '1px solid rgba(255,255,255,.08)';
const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? '' : 's'}`;

/** Time value (Nik, 25 Nov 2026: "Instead of TV can we use a time icon?"): the phone's clock. */
function Clock() {
  return (
    <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flex: 'none', alignSelf: 'center' }}>
      <circle cx="8" cy="8" r="6.6" />
      <path d="M8 4.4V8H5.2" />
    </svg>
  );
}

function Block({ k, p, mask, who, usd, flip }: { k: PKey; p: Part; mask: (s: string) => string; who: string; usd: boolean; flip: () => void }) {
  const def = PARTS.find((x) => x.k === k)!;
  const a = p.all, ok = a >= -0.5, c = a > 0.5 ? G : a < -0.5 ? R : K;
  const word = def.sold ? (ok ? 'kept' : 'lost') : ok ? 'gain' : 'loss';
  const now = def.sold ? p.value - a : p.value;
  const x = def.sold ? (p.value > 0 ? (a / p.value) * 100 : 0) : p.abase > 0 ? (a / p.abase) * 100 : 0;
  const allS = mask(money0(a)), nowS = mask(money0(now)), tvS = p.tv != null ? mask(money0(p.tv)) : null;
  const aria = [`${who}${def.l}, ${nowS} now`, `${word} ${allS}`,
    def.sold ? `${pct(x)} ${ok ? 'captured' : 'lost'}` : `return ${ok ? 'up' : 'down'} ${pct(x)}`,
    tvS ? `${tvS} time value` : ''].filter(Boolean).join(', ');
  return (
    <button type="button" onClick={flip} aria-label={aria} aria-pressed={usd}
      style={{ display: 'flex', flexDirection: 'column', minWidth: 0, width: '100%', padding: 0, margin: 0, border: 0, background: 'none', color: 'inherit', font: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
      <span aria-hidden="true" style={{ fontSize: 14, lineHeight: '18px', color: MU, whiteSpace: 'nowrap' }}>{def.l}</span>
      <span aria-hidden="true" style={{ marginTop: 2, display: 'flex', alignItems: 'baseline', gap: 6, width: '100%', whiteSpace: 'nowrap' }}>
        <span style={{ fontSize: 30, lineHeight: '36px', fontWeight: 700, letterSpacing: '-0.02em', color: K }}>{nowS}</span>
        <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600, color: c }}>({usd ? allS : pct(x)})</span>
        {tvS && (
          <span style={{ marginLeft: 'auto', paddingLeft: 8, display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 14, lineHeight: '18px', color: MU }}>
            <Clock /><span style={{ fontWeight: 600, color: K }}>{tvS}</span>
          </span>
        )}
      </span>
    </button>
  );
}

function Head({ l, r }: { l: string; r: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: '4px 16px', flexWrap: 'wrap' }}>
      <span style={{ fontSize: 20, lineHeight: '24px', fontWeight: 700, color: K }}>{l}</span>
      <span style={{ fontSize: 15, lineHeight: '20px', color: MU, whiteSpace: 'nowrap' }}>{r}</span>
    </div>
  );
}

function Grid({ ps, mask, who, label, usd, flip }: { ps: Parts; mask: (s: string) => string; who: string; label: string; usd: boolean; flip: () => void }) {
  return (
    <div role="list" aria-label={label} style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(min(100%,236px),1fr))', gap: '20px 28px' }}>
      {PARTS.filter((x) => ps[x.k]).map((x) => (
        <div key={x.k} role="listitem" style={{ minWidth: 0 }}><Block k={x.k} p={ps[x.k]!} mask={mask} who={who} usd={usd} flip={flip} /></div>
      ))}
    </div>
  );
}

export function BookTotals({ book, nNames, name, t, mask }: { book: Parts; nNames: number; name: Parts | null; t: string | null; mask: (s: string) => string }) {
  const nl = legsIn(book), nn = name ? legsIn(name) : 0;
  // Click any block and every block's change reads in dollars instead of %, remembered on this browser.
  const [usd, setUsd] = useState(() => { try { return localStorage.getItem('sw-pos-usd') === '1'; } catch { return false; } });
  const flip = () => setUsd((u) => { try { localStorage.setItem('sw-pos-usd', u ? '0' : '1'); } catch { /* private window */ } return !u; });
  return (
    <section aria-label="Your book" className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 16, padding: '16px 0 20px', borderTop: '1px solid rgba(255,255,255,.14)', borderBottom: RULE }}>
      <Head l="Your book" r={`${plural(nNames, 'ticker')} · ${plural(nl, 'leg')}`} />
      <Grid ps={book} mask={mask} who="" label="Your book, each part" usd={usd} flip={flip} />
      {t && name && nn > 0 && (
        <>
          <span aria-hidden="true" style={{ height: 1, background: 'rgba(255,255,255,.08)', margin: '4px 0 0' }} />
          <Head l={t} r={plural(nn, 'leg')} />
          <Grid ps={name} mask={mask} who={`${t} `} label={`${t}, each part`} usd={usd} flip={flip} />
        </>
      )}
    </section>
  );
}
