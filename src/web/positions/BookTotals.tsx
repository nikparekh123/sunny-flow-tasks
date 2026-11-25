// Your book (Nik, 24 Nov 2026: "No need for Today and All time, just all time"): each leg, not Long, Hedge and Income.
// Header: Your book, and on the right how many tickers and legs. Then one block per part the book holds, in this
// order: Shares, Calls bought, Calls sold, Puts bought, Puts sold, in a grid that fills the width on a wide screen and
// is one column on a phone. Each block:
//   "Shares · gain" (or loss; sold parts read kept or lost), muted.
//   The all time gain, loss or kept, big, green or red, never a minus sign.
//   Bought: "$613K now · 1.3% return" (calls and puts bought add "· $91.3K time value").
//   Sold:   "$8.8K now · 68.4% captured · $8.8K time value" (now = the cost to buy back, collected less kept).
// The picked name's own book follows in the same blocks, only the parts it holds.
// Every figure is sunny-home's (payload.brief_inputs.parts, totals.ts), the same numbers the phone reads.

/** A whole-number percent, no sign (Nik, 25 Nov 2026: "Use no decimal in %"). */
const pct = (x: number) => `${Math.round(Math.abs(x))}%`;
/** Whole K and M, no decimals, no sign (Nik, 25 Nov 2026: "Round off the numbers also to be K M no decimals"). */
const money0 = (v: number) => {
  const a = Math.abs(v);
  return a >= 999_500 ? `$${Math.round(a / 1e6)}M` : a >= 999.5 ? `$${Math.round(a / 1e3)}K` : `$${Math.round(a)}`;
};
import { PARTS, legsIn, type PKey, type Part, type Parts } from './totals';
import { G, K, MU, R } from './ui';

const RULE = '1px solid rgba(255,255,255,.08)', SEP = 18;
const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? '' : 's'}`;

function Block({ k, p, mask, who }: { k: PKey; p: Part; mask: (s: string) => string; who: string }) {
  const def = PARTS.find((x) => x.k === k)!;
  const a = p.all, ok = a >= -0.5, c = a > 0.5 ? G : a < -0.5 ? R : K;
  const word = def.sold ? (ok ? 'kept' : 'lost') : ok ? 'gain' : 'loss';
  const now = def.sold ? p.value - a : p.value;
  const x = def.sold ? (p.value > 0 ? (a / p.value) * 100 : 0) : p.abase > 0 ? (a / p.abase) * 100 : 0;
  const big = mask(money0(a)), nowS = mask(money0(now)), tvS = p.tv != null ? mask(money0(p.tv)) : null;
  const aria = [`${who}${def.l}, ${word} ${big}`, `${nowS} now`,
    def.sold ? `${pct(x)} ${ok ? 'captured' : 'lost'}` : `return ${ok ? 'up' : 'down'} ${pct(x)}`,
    tvS ? `${tvS} time value` : ''].filter(Boolean).join(', ');
  // The sub line wraps between its pieces, never inside one; each piece leads with its dot, and the dot that would
  // start a line sits left of the clip, so no line starts or ends on a dot.
  // Condensed (Nik, 25 Nov 2026): the % by the big figure, then "$96K now · $92K TV".
  const segs: [string, string, string][] = [[nowS, 'now', K], ...(tvS ? [[tvS, 'TV', K] as [string, string, string]] : [])];
  return (
    <div role="group" aria-label={aria} style={{ display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      <span aria-hidden="true" style={{ fontSize: 14, lineHeight: '18px', color: MU, whiteSpace: 'nowrap' }}>{def.l} · {word}</span>
      <span aria-hidden="true" style={{ marginTop: 2, display: 'flex', alignItems: 'baseline', gap: 8, color: c, whiteSpace: 'nowrap' }}>
        <span style={{ fontSize: 30, lineHeight: '36px', fontWeight: 700, letterSpacing: '-0.02em' }}>{big}</span>
        <span style={{ fontSize: 17, lineHeight: '22px', fontWeight: 600 }}>{pct(x)}</span>
      </span>
      <span aria-hidden="true" style={{ marginTop: 4, display: 'block', overflow: 'hidden' }}>
        <span style={{ display: 'flex', flexWrap: 'wrap', marginLeft: -SEP, fontSize: 14, lineHeight: '18px', fontWeight: 400, color: MU }}>
          {segs.map(([v, w, col]) => (
            <span key={w} style={{ whiteSpace: 'nowrap' }}>
              <span style={{ display: 'inline-block', width: SEP, textAlign: 'center', userSelect: 'none' }}>·</span>
              <span style={{ fontWeight: 600, color: col }}>{v}</span> {w}
            </span>
          ))}
        </span>
      </span>
    </div>
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

function Grid({ ps, mask, who, label }: { ps: Parts; mask: (s: string) => string; who: string; label: string }) {
  return (
    <div role="list" aria-label={label} style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(min(100%,236px),1fr))', gap: '20px 28px' }}>
      {PARTS.filter((x) => ps[x.k]).map((x) => (
        <div key={x.k} role="listitem" style={{ minWidth: 0 }}><Block k={x.k} p={ps[x.k]!} mask={mask} who={who} /></div>
      ))}
    </div>
  );
}

export function BookTotals({ book, nNames, name, t, mask }: { book: Parts; nNames: number; name: Parts | null; t: string | null; mask: (s: string) => string }) {
  const nl = legsIn(book), nn = name ? legsIn(name) : 0;
  return (
    <section aria-label="Your book" className="tnum" style={{ display: 'flex', flexDirection: 'column', gap: 16, padding: '16px 0 20px', borderTop: '1px solid rgba(255,255,255,.14)', borderBottom: RULE }}>
      <Head l="Your book" r={`${plural(nNames, 'ticker')} · ${plural(nl, 'leg')}`} />
      <Grid ps={book} mask={mask} who="" label="Your book, each part" />
      {t && name && nn > 0 && (
        <>
          <span aria-hidden="true" style={{ height: 1, background: 'rgba(255,255,255,.08)', margin: '4px 0 0' }} />
          <Head l={t} r={plural(nn, 'leg')} />
          <Grid ps={name} mask={mask} who={`${t} `} label={`${t}, each part`} />
        </>
      )}
    </section>
  );
}
