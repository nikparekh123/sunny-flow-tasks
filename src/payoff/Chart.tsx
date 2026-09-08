/**
 * The payoff plot. SVG 1450 × H, contents translated to (OX, OY) = (76, 84),
 * plot W × H = 1362 × 400. Painted in the README's z-order, which matters:
 * bands under gridlines under cone under levels under the fill under the
 * curves under the markers under the spot line under the crosshair.
 *
 * ⚠ THE LABEL BAND IS COLLISION-RESOLVED, NOT ABSOLUTELY POSITIONED. Three
 * rows above the plot, filled nearest-the-plot first; labels within 34px
 * cluster into one `N LEVELS` range; anything that still does not fit is
 * dropped rather than overlapped. The README calls this out as one of the
 * distinctive pieces of the design and says not to replace it with a naive
 * pass. It has not been.
 */
import { useMemo, useRef, useState, useCallback, useEffect } from 'react';
import {
  type Leg, type Ctx, total, bounds, density, NRM, niceStep, place, cluster,
  type LabelItem, money, priceLab, priceShort, signed1, fmtExp,
} from './math';
import type { Layers, TickerBook } from './types';

export const OX = 76, OY = 84, W = 1362, H = 400;
const CONE_H = 150;
const N_PTS = 220;

export interface ChartProps {
  book: TickerBook;
  ctx: Ctx;
  liveLegs: Leg[];
  bookLegs: Leg[];       // the broker's own legs (live), for the book-only curve
  planActive: boolean;
  elapsed: number;
  dte: number;
  sel: string;
  rangePct: number;
  layers: Layers;
  closes: number[];      // last 252 closes, for the time-at-price histogram
}

interface Pt { p: number; v: number }

export function Chart({ book, ctx, liveLegs, bookLegs, planActive, elapsed, dte, sel, rangePct, layers, closes }: ChartProps) {
  const [hoverP, setHoverP] = useState<number | null>(null);
  const raf = useRef<number | null>(null);
  /* scale-to-fit: the 1450px drawing shrinks as one piece on narrower screens */
  const fitRef = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState(1);
  useEffect(() => {
    const el = fitRef.current; if (!el) return;
    const ro = new ResizeObserver(() => setFit(Math.min(1, el.clientWidth / 1450)));
    ro.observe(el); setFit(Math.min(1, el.clientWidth / 1450));
    return () => ro.disconnect();
  }, []);
  const spot = ctx.spot;
  const lo = spot * (1 - rangePct / 100), hi = spot * (1 + rangePct / 100);
  const x = useCallback((p: number) => ((p - lo) / (hi - lo)) * W, [lo, hi]);

  /* ── curves ─────────────────────────────────────────────────────────── */
  const { today, atExp, bookOnly, ymin, ymax, ystep } = useMemo(() => {
    const ps = Array.from({ length: N_PTS + 1 }, (_, i) => lo + ((hi - lo) * i) / N_PTS);
    const today: Pt[] = ps.map((p) => ({ p, v: total(p, elapsed, liveLegs, ctx) }));
    const atExp: Pt[] = ps.map((p) => ({ p, v: total(p, dte, liveLegs, ctx) }));
    const bookOnly: Pt[] | null = planActive ? ps.map((p) => ({ p, v: total(p, elapsed, bookLegs, ctx) })) : null;
    let mn = 0, mx = 0;
    for (const s of [today, atExp, bookOnly ?? []]) for (const q of s) { if (q.v < mn) mn = q.v; if (q.v > mx) mx = q.v; }
    const span = Math.max(mx - mn, 1);
    mn -= span * 0.08; mx += span * 0.08;
    const step = niceStep(span / 5);
    mn = Math.floor(mn / step) * step; mx = Math.ceil(mx / step) * step;
    return { today, atExp, bookOnly, ymin: mn, ymax: mx, ystep: step };
  }, [lo, hi, elapsed, dte, liveLegs, bookLegs, planActive, ctx]);

  const y = useCallback((v: number) => H - ((v - ymin) / (ymax - ymin)) * H, [ymin, ymax]);
  const y0 = y(0);
  const path = (pts: Pt[]) => pts.map((q, i) => `${i ? 'L' : 'M'}${x(q.p).toFixed(1)},${y(q.v).toFixed(1)}`).join('');
  const area = (pts: Pt[]) => path(pts) + `L${W},${y0.toFixed(1)}L0,${y0.toFixed(1)}Z`;

  /* ── breakevens, in view ────────────────────────────────────────────── */
  const bes = useMemo(() => bounds(liveLegs, dte, ctx).bes.filter((b) => b > lo && b < hi), [liveLegs, dte, ctx, lo, hi]);

  /* ── gridlines + axis labels ────────────────────────────────────────── */
  const ygrid = useMemo(() => {
    const out: number[] = [];
    for (let v = ymin; v <= ymax + 1e-6; v += ystep) out.push(Math.round(v * 100) / 100);
    return out;
  }, [ymin, ymax, ystep]);
  const xgrid = useMemo(() => {
    const step = niceStep((hi - lo) / 8);
    const out: number[] = [];
    for (let p = Math.ceil(lo / step) * step; p <= hi; p += step) out.push(Math.round(p * 100) / 100);
    return out;
  }, [lo, hi]);

  /* ── assignment regions ─────────────────────────────────────────────── */
  const assign = useMemo(() => {
    const zones: { from: number; to: number; k: number; label: string }[] = [];
    for (const l of liveLegs) {
      if (l.kind === 'stock' || l.qty >= 0) continue;
      const n = -l.qty;
      if (l.kind === 'call') zones.push({ from: Math.max(l.strike, lo), to: hi, k: l.strike, label: `${n} call${n > 1 ? 's' : ''} above ${priceShort(l.strike)}` });
      else zones.push({ from: lo, to: Math.min(l.strike, hi), k: l.strike, label: `${n} put${n > 1 ? 's' : ''} below ${priceShort(l.strike)}` });
    }
    return zones.filter((z) => z.to > z.from);
  }, [liveLegs, lo, hi]);

  /* ── the probability cone ───────────────────────────────────────────── */
  const cone = useMemo(() => {
    if (!layers.cone) return null;
    const ps = Array.from({ length: 160 }, (_, i) => lo + ((hi - lo) * i) / 159);
    const d = ps.map((p) => density(p, dte, ctx));
    const dmax = Math.max(...d, 1e-12);
    const pts = ps.map((p, i) => `${i ? 'L' : 'M'}${x(p).toFixed(1)},${(H - (d[i] / dmax) * CONE_H).toFixed(1)}`).join('');
    const s = ctx.iv * ctx.ivMult * Math.sqrt(Math.max(dte, 1) / 365);
    const sig = (k: number) => spot * Math.exp(k * s - 0.5 * s * s);
    return { path: pts + `L${W},${H}L0,${H}Z`, marks: [-2, -1, 1, 2].map((k) => ({ k, p: sig(k) })) };
  }, [layers.cone, lo, hi, dte, ctx, spot, x]);

  /* ── time-at-price histogram ────────────────────────────────────────── */
  const hist = useMemo(() => {
    if (!layers.hist || !closes.length) return null;
    const bins = 60, counts = new Array(bins).fill(0);
    for (const c of closes) { const i = Math.floor(((c - lo) / (hi - lo)) * bins); if (i >= 0 && i < bins) counts[i]++; }
    const mx = Math.max(...counts, 1);
    return counts.map((n, i) => ({ x: (i / bins) * W, w: W / bins - 1, h: (n / mx) * 36 }));
  }, [layers.hist, closes, lo, hi]);

  /* ── the label band above the plot ──────────────────────────────────── */
  const labels = useMemo(() => {
    const items: LabelItem[] = [];
    const inView = (p: number) => p > lo && p < hi;
    const lab = (name: string, price: number, nameInk?: string): LabelItem => ({
      kind: 'lab', anchor: 'mid', l: x(price), w: Math.max(name.length, priceLab(price).length) * 6.4,
      name, val: priceLab(price), nameInk, valInk: 'var(--ink)',
    });
    if (layers.ema) for (const [n, p] of book.emas) if (inView(p)) items.push(lab(n, p, 'var(--mute)'));
    if (layers.sr) for (const [n, p] of book.levels) if (inView(p)) items.push(lab(n, p, 'var(--ink-2)'));
    if (layers.targets && book.target && inView(book.target.median)) items.push(lab('ANALYST MEDIAN', book.target.median, 'var(--plum)'));
    const clustered = cluster(items);
    if (layers.assign) for (const z of assign) if (inView(z.k)) clustered.push({
      kind: 'assign', anchor: 'mid', l: x(z.k), w: Math.max(10, z.label.length) * 6.4,
      name: 'ASSIGNMENT', val: z.label, nameInk: 'var(--assign)', valInk: 'var(--ink-2)',
    });
    return place(clustered);
  }, [book, layers, assign, lo, hi, x]);

  /* ── hover ──────────────────────────────────────────────────────────── */
  const onMove = (e: React.MouseEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const px = (e.clientX - rect.left) / fit - OX;
    if (raf.current) cancelAnimationFrame(raf.current);
    raf.current = requestAnimationFrame(() => {
      setHoverP(px < 0 || px > W ? null : lo + (px / W) * (hi - lo));
    });
  };
  const onLeave = () => { if (raf.current) cancelAnimationFrame(raf.current); setHoverP(null); };

  const chanceAbove = (p: number) => {
    const s = ctx.iv * ctx.ivMult * Math.sqrt(Math.max(dte, 1) / 365);
    const z = (Math.log(p / spot) + 0.5 * s * s) / s;
    return NRM(-z);
  };

  const chipY = hist ? 459 : 420;
  const canvasH = OY + chipY + 30 + 34;
  const clipPos = `clip-pos-${book.ticker}`, clipNeg = `clip-neg-${book.ticker}`;
  const gradPos = `grad-pos-${book.ticker}`, gradNeg = `grad-neg-${book.ticker}`;

  return (
    <div className="po-fit" ref={fitRef} style={{ height: canvasH * fit }}>
    <div className="po-canvas" style={{ height: canvasH, transform: fit < 1 ? `scale(${fit})` : undefined }} onMouseMove={onMove} onMouseLeave={onLeave}>
      <svg width={1450} height={canvasH} style={{ position: 'absolute', inset: 0, overflow: 'visible' }}>
        <defs>
          <clipPath id={clipPos}><rect x={0} y={-40} width={W} height={y0 + 40} /></clipPath>
          <clipPath id={clipNeg}><rect x={0} y={y0} width={W} height={H - y0 + 60} /></clipPath>
          <linearGradient id={gradPos} gradientUnits="userSpaceOnUse" x1={0} y1={0} x2={0} y2={y0}>
            <stop offset={0} stopColor="var(--gain-bar)" stopOpacity={0.55} />
            <stop offset={1} stopColor="var(--gain-bar)" stopOpacity={0.06} />
          </linearGradient>
          <linearGradient id={gradNeg} gradientUnits="userSpaceOnUse" x1={0} y1={H} x2={0} y2={y0}>
            <stop offset={0} stopColor="var(--loss-bar)" stopOpacity={0.48} />
            <stop offset={1} stopColor="var(--loss-bar)" stopOpacity={0.06} />
          </linearGradient>
        </defs>
        <g transform={`translate(${OX},${OY})`}>
          {/* 1 · assignment bands */}
          {layers.assign && assign.map((z, i) => (
            <g key={'az' + i}>
              <rect x={x(z.from)} y={0} width={x(z.to) - x(z.from)} height={H} fill="var(--assign)" opacity={0.035} />
              {z.k > lo && z.k < hi && <line x1={x(z.k)} x2={x(z.k)} y1={0} y2={H} stroke="var(--assign)" strokeWidth={1.5} />}
            </g>
          ))}
          {/* 2 · analyst target band */}
          {layers.targets && book.target && (
            <g>
              <rect x={x(Math.max(book.target.low, lo))} y={0} width={Math.max(0, x(Math.min(book.target.high, hi)) - x(Math.max(book.target.low, lo)))} height={H} fill="var(--plum)" opacity={0.05} />
              {book.target.median > lo && book.target.median < hi && <line x1={x(book.target.median)} x2={x(book.target.median)} y1={0} y2={H} stroke="var(--plum)" strokeWidth={1.5} />}
              {[book.target.low, book.target.high].filter((p) => p > lo && p < hi).map((p) => (
                <line key={p} x1={x(p)} x2={x(p)} y1={0} y2={H} stroke="var(--plum)" strokeWidth={1} strokeDasharray="3 3" />
              ))}
            </g>
          )}
          {/* 3 · y gridlines */}
          {ygrid.map((v) => <line key={'g' + v} x1={0} x2={W} y1={y(v)} y2={y(v)} stroke="var(--grid)" strokeWidth={1} />)}
          {/* 4 · probability cone */}
          {cone && (
            <g>
              <path d={cone.path} fill="var(--update)" fillOpacity={0.085} stroke="var(--update)" strokeOpacity={0.45} strokeWidth={1.25} />
              {cone.marks.filter((m) => m.p > lo && m.p < hi).map((m) => (
                <line key={m.k} x1={x(m.p)} x2={x(m.p)} y1={H - CONE_H} y2={H} stroke="var(--update)" strokeOpacity={0.5} strokeWidth={1} strokeDasharray="3 3" />
              ))}
            </g>
          )}
          {/* last 5 days band */}
          {layers.last5 && book.d5 && (
            <rect x={x(Math.max(book.d5[0], lo))} y={0} width={Math.max(0, x(Math.min(book.d5[1], hi)) - x(Math.max(book.d5[0], lo)))} height={H} fill="var(--ink-3)" opacity={0.06} />
          )}
          {/* 5 · EMAs */}
          {layers.ema && book.emas.filter(([, p]) => p > lo && p < hi).map(([n, p]) => (
            <line key={n} x1={x(p)} x2={x(p)} y1={0} y2={H} stroke="var(--hair)" strokeWidth={1} strokeDasharray="2 4" />
          ))}
          {/* 6 · support / resistance */}
          {layers.sr && book.levels.filter(([, p]) => p > lo && p < hi).map(([n, p]) => (
            <line key={n + p} x1={x(p)} x2={x(p)} y1={0} y2={H} stroke="var(--ink-2)" strokeOpacity={0.5} strokeWidth={1} />
          ))}
          {/* 7 · area fill under the today curve */}
          <path d={area(today)} fill={`url(#${gradPos})`} clipPath={`url(#${clipPos})`} />
          <path d={area(today)} fill={`url(#${gradNeg})`} clipPath={`url(#${clipNeg})`} />
          {/* 8 · zero line */}
          <line x1={0} x2={W} y1={y0} y2={y0} stroke="var(--dim)" strokeWidth={1} />
          {/* 9 · book-only curve */}
          {bookOnly && <path d={path(bookOnly)} fill="none" stroke="var(--faint)" strokeWidth={1.5} />}
          {/* 10 · at-expiration reference, when scrubbing before expiry */}
          {elapsed < dte && <path d={path(atExp)} fill="none" stroke="var(--mute)" strokeWidth={1.5} strokeDasharray="2 5" strokeLinecap="round" opacity={0.85} />}
          {/* 11 · the main curve, gain above zero and loss below */}
          <path d={path(today)} fill="none" stroke="var(--gain)" strokeWidth={3} strokeLinejoin="round" clipPath={`url(#${clipPos})`} strokeDasharray={planActive ? '9 5' : undefined} />
          <path d={path(today)} fill="none" stroke="var(--loss)" strokeWidth={3} strokeLinejoin="round" clipPath={`url(#${clipNeg})`} strokeDasharray={planActive ? '9 5' : undefined} />
          {/* 12 · breakeven markers */}
          {bes.map((b, i) => (
            <g key={'be' + i}>
              <line x1={x(b)} x2={x(b)} y1={y0} y2={410} stroke="var(--faint)" strokeWidth={1} strokeDasharray="3 3" />
              <circle cx={x(b)} cy={y0} r={3.5} fill="var(--page)" stroke="var(--faint)" strokeWidth={1.5} />
            </g>
          ))}
          {/* 13 · spot line */}
          {spot > lo && spot < hi && <line x1={x(spot)} x2={x(spot)} y1={-10} y2={H + 10} stroke="var(--neon)" strokeOpacity={0.75} strokeWidth={1.5} />}
          {/* 14 · time at price */}
          {hist && (
            <g>
              {hist.map((b, i) => <rect key={i} x={b.x} y={448 - b.h} width={b.w} height={b.h} rx={1} fill="var(--hair)" />)}
              <line x1={0} x2={W} y1={448} y2={448} stroke="var(--rule)" strokeWidth={1} />
            </g>
          )}
          {/* 15 · hover crosshair */}
          {hoverP != null && (
            <g>
              <line x1={x(hoverP)} x2={x(hoverP)} y1={0} y2={H} stroke="var(--ink)" strokeOpacity={0.35} strokeWidth={1} />
              <circle cx={x(hoverP)} cy={y(total(hoverP, elapsed, liveLegs, ctx))} r={4.5} fill="var(--page)" stroke="var(--ink)" strokeWidth={2} />
              <circle cx={x(hoverP)} cy={y(total(hoverP, dte, liveLegs, ctx))} r={3.5} fill="var(--ink)" fillOpacity={0.5} />
            </g>
          )}
        </g>
      </svg>

      {/* y labels */}
      {ygrid.map((v) => <div key={'yl' + v} className="po-ylab num" style={{ top: OY + y(v) }}>{money(v)}</div>)}
      {/* x labels */}
      {xgrid.map((p) => <div key={'xl' + p} className="po-xlab num" style={{ left: OX + x(p), top: OY + chipY - 6 }}>{priceLab(p)}</div>)}
      {hist && <div className="po-ylab" style={{ top: OY + 428, fontSize: 9, letterSpacing: 1.4, textTransform: 'uppercase' }}>days</div>}

      {/* curve name tags at the left edge; the second steps aside when the
          curves meet there, which for a LEAP book is most of the time */}
      {(() => {
        const t1 = OY + y(today[0].v);
        let t2 = OY + y(atExp[0].v);
        if (Math.abs(t2 - t1) < 16) t2 = t1 + (t2 >= t1 ? 16 : -16);
        return (
          <>
            <div className="po-tag" style={{ top: t1, color: 'var(--mute)' }}>
              {elapsed === 0 ? 'Value today' : elapsed >= dte ? 'At expiration' : `${dte - elapsed}d left`}
            </div>
            {elapsed < dte && <div className="po-tag" style={{ top: t2, color: 'var(--faint)' }}>At expiration</div>}
          </>
        );
      })()}

      {/* the label band */}
      {labels.map((l, i) => (
        <div key={i} className="po-lvl" style={{ left: OX + l.l, top: l.t, transform: l.anchor === 'mid' ? 'translateX(-50%)' : undefined, alignItems: 'center' }}>
          <span className="n" style={{ color: l.nameInk ?? 'var(--mute)' }}>{l.name}</span>
          <span className="v num" style={{ color: l.valInk ?? 'var(--ink)' }}>{l.val}</span>
        </div>
      ))}

      {/* chips below the axis */}
      {bes.map((b, i) => <div key={'bc' + i} className="po-chip be num" style={{ left: OX + x(b), top: OY + chipY + 6 }}>BE {priceLab(b)}</div>)}
      {spot > lo && spot < hi && <div className="po-chip now num" style={{ left: OX + x(spot), top: OY + chipY + 36 }}>NOW {priceLab(spot)}</div>}

      {/* hover card */}
      {hoverP != null && (() => {
        const px = OX + x(hoverP);
        const flip = px > 1450 - 250;
        const pl = total(hoverP, dte, liveLegs, ctx), tod = total(hoverP, elapsed, liveLegs, ctx);
        return (
          <div className="po-hover" style={{ left: px + (flip ? -14 : 14), transform: flip ? 'translateX(-100%)' : undefined }}>
            <div><span className="p num">{priceLab(hoverP)}</span><span className="pc num">{signed1((hoverP / spot - 1) * 100)}%</span></div>
            <div className="hr" />
            <div className="r"><span className="k">{fmtExp(sel, ctx.today)}</span><span className={'v num ' + (pl < 0 ? 'loss' : 'gain')}>{money(pl)}</span></div>
            {bookOnly && <div className="r"><span className="k">Book only</span><span className={'v num ' + (total(hoverP, elapsed, bookLegs, ctx) < 0 ? 'loss' : 'gain')}>{money(total(hoverP, elapsed, bookLegs, ctx))}</span></div>}
            <div className="r"><span className="k">Today</span><span className={'v num ' + (tod < 0 ? 'loss' : 'gain')}>{money(tod)}</span></div>
            <div className="r"><span className="k">Chance above</span><span className="v num">{Math.round(chanceAbove(hoverP) * 100)}%</span></div>
          </div>
        );
      })()}
    </div>
    </div>
  );
}
