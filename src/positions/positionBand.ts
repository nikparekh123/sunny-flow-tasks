/* ============================================================
   positionBand.ts — Position Lens band, app module.
   Ported from the Claude-design handoff (position-band.js):
   • takes an injected per-ticker data object (no demo data)
   • no random-walk price sim — real static prices
   • tooltip mounts inside the nearest .dash so tokens resolve
   • mountBand(el, pos, opts) → cleanup()
   ============================================================ */
import './position-band.css';

export interface BandOption {
  strike: number;
  qty: number;
  prem: number;
  side: 'sold' | 'bought';
  sold?: string;
  bought?: string;
  expires?: string;
  closed?: string;
  dte?: number;
  status: 'active' | 'expired';
}
export interface BandLot { p: number; sh: number; date: string; }
export interface BandClose { price: number; date: string; }
export interface BandPosition {
  t: string;
  name: string;
  sector: string;
  range: [number, number];
  current: number;
  dayAgo: number;
  weekAgo: number;
  monthAgo: number;
  avgCost: number;
  totalShares: number;
  breakeven: number;
  earningsDate?: string | null;
  expectedMovePct?: number | null;
  lots: BandLot[];
  calls: BandOption[];
  puts: BandOption[];
  closes: BandClose[];
  oi?: { strike: number; n: number }[] | null;
  summary?: string;
  unrealizedPct?: number;
}
export interface MountOpts {
  chrome?: 'band' | 'full';
  hidden?: string[];
  toolbar?: boolean;
  scrubber?: boolean;
}

export const LAYERS = ['shares', 'call-sold', 'call-bought', 'put-sold', 'put-bought', 'closed', 'recent', 'closes', 'distance', 'be', 'zone', 'earnings', 'oi', 'annotations'];
export const CURATED_HIDDEN = ['oi', 'closes', 'annotations'];

const todayIso = () => new Date().toISOString().slice(0, 10);

/* ---- date helpers ---- */
function parseD(s: string) { const [y, m, d] = s.split('-').map(Number); return new Date(y, m - 1, d); }
function fmtDate(dt: Date) { return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }); }

/* ---- number helpers ---- */
function fmt$(n: number, d = 2) { const s = Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d }); return (n < 0 ? '−' : '') + '$' + s; }
function fmtPct(n: number, d = 2) { return (n >= 0 ? '+' : '−') + Math.abs(n).toFixed(d) + '%'; }
function esc(s: string) { return s.replace(/"/g, '&quot;'); }

/* open-interest profile — synthetic fallback when real OI absent (Phase C
   injects pos.oi). Kept hidden by default. */
function buildOI(p: BandPosition): { strike: number; n: number }[] {
  if (p.oi && p.oi.length) return p.oi;
  const [min, max] = p.range;
  const N = 24, step = (max - min) / N;
  const userStrikes = [...p.calls, ...p.puts].filter((o) => o.status === 'active').map((o) => o.strike);
  const bars: { strike: number; oi: number }[] = [];
  for (let i = 0; i <= N; i++) {
    const strike = min + i * step;
    let oi = Math.exp(-Math.pow((strike - p.current) / ((max - min) * 0.22), 2)) * 100;
    const roundStep = (max - min) > 400 ? 50 : (max - min) > 150 ? 20 : 10;
    if (Math.abs(strike % roundStep) < step * 0.5) oi += 30;
    userStrikes.forEach((s) => { if (Math.abs(strike - s) < step) oi += 55; });
    oi += (Math.sin(strike * 1.7) + 1) * 14;
    bars.push({ strike, oi });
  }
  const maxOI = Math.max(...bars.map((b) => b.oi));
  return bars.map((b) => ({ strike: b.strike, n: b.oi / maxOI }));
}

/* ---- tooltip builders ---- */
const ttRow = (k: string, v: string, c = '') => `<div class="tt-row"><span class="k">${k}</span><span class="v ${c}">${v}</span></div>`;
const ttBig = (k: string, v: string, c = '') => `<div class="tt-row big"><span class="k">${k}</span><span class="v ${c}">${v}</span></div>`;

function ttShareLot(lot: BandLot, p: BandPosition) {
  const cost = lot.sh * lot.p, mv = lot.sh * p.current, upnl = mv - cost, upct = (p.current / lot.p - 1) * 100;
  return `<div class="tt-head"><span class="tag shares">Share lot</span><span class="state">${p.t}</span></div>
    ${ttRow('Bought', `${lot.sh} sh @ ${fmt$(lot.p)}`)}${ttRow('Cost basis', fmt$(cost, 0))}${ttRow('Bought on', lot.date)}
    <div class="tt-bar"></div>${ttRow('Now', fmt$(p.current))}${ttRow('Lot value', fmt$(mv, 0))}
    ${ttBig('Unrealized', `${fmt$(upnl, 0)} · ${fmtPct(upct, 1)}`, upnl >= 0 ? 'pos' : 'neg')}`;
}
function ttAvgCost(p: BandPosition) {
  const cost = p.totalShares * p.avgCost, mv = p.totalShares * p.current, upnl = mv - cost, upct = (p.current / p.avgCost - 1) * 100;
  return `<div class="tt-head"><span class="tag shares">Average cost</span><span class="state">${p.t} · ${p.lots.length} lot${p.lots.length === 1 ? '' : 's'}</span></div>
    ${ttRow('Total shares', p.totalShares.toLocaleString())}${ttRow('Avg price', fmt$(p.avgCost))}${ttRow('Total cost', fmt$(cost, 0))}
    <div class="tt-bar"></div>${ttRow('Mark', fmt$(p.current))}${ttRow('Position value', fmt$(mv, 0))}
    ${ttBig('Unrealized', `${fmt$(upnl, 0)} · ${fmtPct(upct, 1)}`, upnl >= 0 ? 'pos' : 'neg')}`;
}
function ttOption(o: BandOption, p: BandPosition, kind: 'call' | 'put') {
  const totalPrem = o.qty * o.prem * 100, active = o.status === 'active', sold = o.side === 'sold';
  const dist = o.strike - p.current, distPct = (dist / p.current) * 100;
  const itm = (kind === 'call' && p.current > o.strike) || (kind === 'put' && p.current < o.strike);
  const tagCls = `${kind}-${sold ? 'sold' : 'bought'}`;
  const premCls = kind === 'call' ? 'neon' : 'warn';
  let foot: string;
  if (active) {
    if (itm) foot = `<div class="tt-foot warn">⚠ ITM — ${kind === 'call' ? (sold ? 'assignment risk live' : 'in profit') : (sold ? 'assignment risk' : 'protection live')}</div>`;
    else if (Math.abs(distPct) < 2) foot = `<div class="tt-foot warn">⚠ Near the money</div>`;
    else foot = `<div class="tt-foot ${kind === 'call' ? 'neon' : 'warn'}">${fmtPct(Math.abs(distPct), 1)} OTM${o.dte != null ? ` · ${o.dte}d to expiry` : ''}</div>`;
  } else foot = `<div class="tt-foot">${sold ? '✓ Closed · premium kept' : '✓ Closed / expired'}</div>`;
  return `<div class="tt-head"><span class="tag ${tagCls}">${sold ? 'Sold' : 'Bought'} ${kind}</span><span class="state ${active ? 'active' : ''}">${active ? '● ACTIVE' : '○ CLOSED'}</span></div>
    ${ttRow('Strike', fmt$(o.strike, 0))}${ttRow('Contracts', `${o.qty} × ${fmt$(o.prem)}`)}
    ${ttBig(sold ? 'Premium kept' : 'Premium paid', `${sold ? '+' : '−'}${fmt$(totalPrem, 0)}`, premCls)}
    <div class="tt-bar"></div>${ttRow(active ? (sold ? 'Sold' : 'Bought') : 'Opened', o.sold || o.bought || '—')}
    ${active ? ttRow('Expires', `${o.expires || '—'}${o.dte != null ? ` · ${o.dte}d` : ''}`) : ttRow('Closed', o.closed || '—')}
    ${active ? ttRow(`Spot to ${kind}`, `${fmt$(dist)} · ${fmtPct(distPct, 1)}${itm ? ' ITM' : ' OTM'}`, itm ? 'warn' : (kind === 'call' ? 'neon' : 'warn')) : ''}${foot}`;
}
function ttLive(p: BandPosition) {
  const upnl = (p.current - p.avgCost) * p.totalShares;
  return `<div class="tt-head"><span class="tag live">● Live</span><span class="state active">${p.t}</span></div>
    ${ttBig('Spot', fmt$(p.current))}${ttRow('Avg cost', fmt$(p.avgCost))}${ttRow('Breakeven', fmt$(p.breakeven))}
    <div class="tt-bar"></div>${ttRow('Position', `${p.totalShares.toLocaleString()} sh`)}
    ${ttBig('Unrealized', `${fmt$(upnl, 0)} · ${fmtPct(p.unrealizedPct ?? (p.current / p.avgCost - 1) * 100, 2)}`, upnl >= 0 ? 'pos' : 'neg')}`;
}
function ttEarnings(p: BandPosition) {
  if (!p.earningsDate || p.expectedMovePct == null) return '';
  const lo = p.current * (1 - p.expectedMovePct / 100), hi = p.current * (1 + p.expectedMovePct / 100);
  const dt = parseD(p.earningsDate), days = Math.round((dt.getTime() - parseD(todayIso()).getTime()) / 86400000);
  return `<div class="tt-head"><span class="tag earnings">Next earnings</span><span class="state">${days}d out</span></div>
    ${ttBig('Report date', fmtDate(dt))}${ttRow('Implied move', `±${p.expectedMovePct.toFixed(1)}%`)}
    <div class="tt-bar"></div>${ttRow('Expected range', `${fmt$(lo, 0)} – ${fmt$(hi, 0)}`)}
    <div class="tt-foot">Strikes inside this band carry post-event assignment risk.</div>`;
}

/* ---- geometry ---- */
const W = 1200, padL = 80, padR = 80, plotW = W - padL - padR, H = 340;
const axisY = 188;

/* ---- band renderer ---- */
function renderBand(p: BandPosition): string {
  const [min, max] = p.range;
  const xOf = (price: number) => padL + ((price - min) / (max - min)) * plotW;
  const liveX = xOf(p.current);
  const parts: string[] = [];

  const activeCall = p.calls.find((c) => c.status === 'active');
  const activePut = p.puts.find((c) => c.status === 'active');

  parts.push(`<text x="${padL + 4}" y="94" font-family="DM Mono" font-size="9" fill="#d2e632" fill-opacity=".42" letter-spacing="2px">↑ CALLS</text>`);
  parts.push(`<text x="${padL + 4}" y="${H - 26}" font-family="DM Mono" font-size="9" fill="#e0c060" fill-opacity=".42" letter-spacing="2px">↓ PUTS</text>`);

  // open-interest profile
  const oi = buildOI(p);
  const barW = (plotW / oi.length) * 0.5;
  parts.push(`<g class="kind-oi">`);
  oi.forEach((b) => {
    if (b.strike < min || b.strike > max) return;
    const x = xOf(b.strike), h = 8 + b.n * 46;
    parts.push(`<rect x="${(x - barW / 2).toFixed(1)}" y="${(axisY - h).toFixed(1)}" width="${barW.toFixed(1)}" height="${(h * 2).toFixed(1)}" fill="#6aa8e0" fill-opacity="${(0.08 + b.n * 0.20).toFixed(3)}" rx="1"/>`);
  });
  parts.push(`<text x="${W - padR - 4}" y="${H - 26}" text-anchor="end" font-family="DM Mono" font-size="9" fill="#6aa8e0" fill-opacity=".6" letter-spacing="1.6px">OPEN INTEREST</text>`);
  parts.push(`</g>`);

  // earnings expected-move bounds (only when we have IV-derived move)
  if (p.earningsDate && p.expectedMovePct != null) {
    const elo = p.current * (1 - p.expectedMovePct / 100), ehi = p.current * (1 + p.expectedMovePct / 100);
    if (elo >= min && ehi <= max) {
      const x1 = xOf(elo), x2 = xOf(ehi);
      const dt = parseD(p.earningsDate), days = Math.round((dt.getTime() - parseD(todayIso()).getTime()) / 86400000);
      parts.push(`<g class="kind-earnings">
        <line x1="${x1}" y1="80" x2="${x1}" y2="${H - 26}" stroke="#a78bfa" stroke-opacity=".6" stroke-width="1.5" stroke-dasharray="4 3"/>
        <line x1="${x2}" y1="80" x2="${x2}" y2="${H - 26}" stroke="#a78bfa" stroke-opacity=".6" stroke-width="1.5" stroke-dasharray="4 3"/>
        <text class="hot" x="${(x1 + x2) / 2}" y="89" text-anchor="middle" font-family="DM Mono" font-size="9.5" fill="#a78bfa" letter-spacing=".6px" data-tip="${esc(ttEarnings(p))}">E ${days}d · ±${p.expectedMovePct.toFixed(1)}%</text>
      </g>`);
    }
  }

  // defined-risk zone
  if (activeCall && activePut) {
    const x1 = xOf(activePut.strike), x2 = xOf(activeCall.strike);
    parts.push(`<g class="kind-zone">
      <rect x="${Math.min(x1, x2)}" y="${axisY - 10}" width="${Math.abs(x2 - x1)}" height="20" fill="#d2e632" fill-opacity=".10"/>
      <line x1="${x1}" y1="${axisY - 10}" x2="${x1}" y2="${axisY + 10}" stroke="#d2e632" stroke-opacity=".45"/>
      <line x1="${x2}" y1="${axisY - 10}" x2="${x2}" y2="${axisY + 10}" stroke="#d2e632" stroke-opacity=".45"/>
    </g>`);
  }

  // axis
  parts.push(`<g class="fx-keep">
    <line x1="${padL}" y1="${axisY}" x2="${W - padR}" y2="${axisY}" stroke="#326e64" stroke-opacity=".55"/>
    <line x1="${padL}" y1="${axisY - 4}" x2="${padL}" y2="${axisY + 4}" stroke="#468278"/>
    <line x1="${W - padR}" y1="${axisY - 4}" x2="${W - padR}" y2="${axisY + 4}" stroke="#468278"/>
    <text x="${padL}" y="${H - 8}" text-anchor="middle" font-family="DM Mono" font-size="10" fill="#468278" letter-spacing="1.4">52w low · $${min}</text>
    <text x="${W - padR}" y="${H - 8}" text-anchor="middle" font-family="DM Mono" font-size="10" fill="#468278" letter-spacing="1.4">52w high · $${max}</text>
  </g>`);

  // recent-path mini-track
  {
    const pts = [
      { k: '1M', v: p.monthAgo }, { k: '1W', v: p.weekAgo }, { k: '1D', v: p.dayAgo }, { k: 'NOW', v: p.current },
    ];
    const vs = pts.map((o) => o.v); const rmin = Math.min(...vs), rmax = Math.max(...vs);
    const pad = (rmax - rmin) * 0.18 || 1;
    const lo = rmin - pad, hi = rmax + pad;
    const tx = (v: number) => padL + ((v - lo) / (hi - lo)) * plotW;
    const ty = 30;
    const up = p.current >= p.monthAgo;
    const col = up ? '#a8d4a0' : '#e87060';
    parts.push(`<g class="kind-recent">`);
    parts.push(`<text x="${padL}" y="16" font-family="DM Mono" font-size="9" fill="#468278" letter-spacing="2px">RECENT PATH · 30D</text>`);
    let d = '';
    pts.forEach((o, i) => { d += (i ? 'L' : 'M') + tx(o.v).toFixed(1) + ' ' + ty; });
    parts.push(`<path d="${d}" fill="none" stroke="${col}" stroke-width="2" stroke-opacity=".5" stroke-linecap="round"/>`);
    pts.forEach((o) => {
      const x = tx(o.v), isNow = o.k === 'NOW';
      parts.push(`<circle cx="${x.toFixed(1)}" cy="${ty}" r="${isNow ? 4 : 2.6}" fill="${isNow ? '#faf5f0' : col}" ${isNow ? '' : 'fill-opacity=".8"'}/>`);
      parts.push(`<text x="${x.toFixed(1)}" y="${ty - 9}" text-anchor="middle" font-family="DM Mono" font-size="9" fill="${isNow ? '#faf5f0' : '#a8c4c0'}" letter-spacing="1px" font-weight="500">${o.k}</text>`);
      parts.push(`<text x="${x.toFixed(1)}" y="${ty + 15}" text-anchor="middle" font-family="DM Mono" font-size="8.5" fill="#468278" letter-spacing=".4px">$${o.v.toFixed(o.v > 300 ? 0 : 1)}</text>`);
    });
    parts.push(`</g>`);
  }

  // breakeven
  parts.push(`<g class="kind-be">
    <line x1="${xOf(p.breakeven)}" y1="82" x2="${xOf(p.breakeven)}" y2="${H - 22}" stroke="#a8c4c0" stroke-width="1" stroke-dasharray="3 3" opacity=".45"/>
    <text x="${xOf(p.breakeven)}" y="${axisY - 58}" text-anchor="middle" font-family="DM Mono" font-size="9" fill="#a8c4c0" letter-spacing="1.2" opacity=".85">B/E $${p.breakeven.toFixed(0)}</text>
  </g>`);

  // share lots
  const lotsY = axisY - 62;
  parts.push(`<g class="kind-shares">`);
  {
    const x = xOf(p.avgCost);
    parts.push(`<g class="te" data-d="${p.lots.length ? p.lots.reduce((a, b) => (a.date < b.date ? a : b)).date : todayIso()}">
      <circle class="hot" cx="${x}" cy="${lotsY}" r="13" fill="transparent" stroke="#faf5f0" stroke-width="1.5" opacity=".5" data-tip="${esc(ttAvgCost(p))}"/>
      <text x="${x}" y="${lotsY - 19}" text-anchor="middle" font-family="DM Mono" font-size="9" fill="#faf5f0" opacity=".75" letter-spacing="1.4">AVG · $${p.avgCost.toFixed(0)}</text>
    </g>`);
  }
  p.lots.forEach((lot) => {
    const x = xOf(lot.p), r = 4 + Math.min(7, lot.sh / 60);
    parts.push(`<circle class="hot te" data-d="${lot.date}" cx="${x}" cy="${lotsY}" r="${r}" fill="transparent" stroke="#faf5f0" stroke-width="1.5" opacity=".95" data-tip="${esc(ttShareLot(lot, p))}"/>`);
  });
  parts.push(`</g>`);

  // calls
  const callY = axisY - 30;
  p.calls.forEach((c) => {
    const x = xOf(c.strike), tip = esc(ttOption(c, p, 'call'));
    const kindCls = c.status === 'active' ? (c.side === 'sold' ? 'kind-call-sold' : 'kind-call-bought') : 'kind-closed';
    const dd = c.status === 'active' ? c.sold : c.closed;
    if (c.status === 'active') {
      const tailH = Math.min(40, Math.max(18, c.prem * 2.2));
      const strikeY = callY - 5 - tailH - 12, premY = strikeY - 13;
      const verb = c.side === 'sold' ? 'CALL' : '+ CALL', sign = c.side === 'sold' ? '+' : '−';
      parts.push(`<g class="${kindCls} te" data-d="${dd || ''}">
        <line x1="${x}" y1="${callY - 5}" x2="${x}" y2="${callY - 5 - tailH}" stroke="#d2e632" stroke-width="1.5"/>
        <circle class="armed-halo" cx="${x}" cy="${callY}" r="12" fill="#d2e632"/>
        ${c.side === 'sold'
          ? `<circle class="hot armed" data-role="call-dot" cx="${x}" cy="${callY}" r="6" fill="#d2e632" data-tip="${tip}"/>`
          : `<circle class="hot armed bought" data-role="call-dot" cx="${x}" cy="${callY}" r="7" fill="transparent" stroke="#d2e632" stroke-width="2" data-tip="${tip}"/>`}
        <text x="${x}" y="${premY}" text-anchor="middle" font-family="DM Mono" font-size="9" fill="#d2e632" fill-opacity=".75" letter-spacing="1px" stroke="#061a10" stroke-width="3" stroke-linejoin="round" paint-order="stroke fill">${sign}$${c.prem.toFixed(2)}</text>
        <text x="${x}" y="${strikeY}" text-anchor="middle" font-family="DM Mono" font-size="10" fill="#d2e632" letter-spacing="1px" font-weight="500" stroke="#061a10" stroke-width="3" stroke-linejoin="round" paint-order="stroke fill">${verb} $${c.strike}</text>
      </g>`);
    } else {
      parts.push(`<g class="${kindCls} te" data-d="${dd || ''}"><circle class="hot" cx="${x}" cy="${callY}" r="5" fill="transparent" stroke="#d2e632" stroke-width="1.5" opacity=".35" data-tip="${tip}"/></g>`);
    }
  });

  // distance brackets
  const arrowAt = (x: number, y: number, dir: string, c: string) => dir === 'left'
    ? `<path class="dist-arrow ${c}" d="M${x - 1},${y} l5,-4 l0,8 z"/>`
    : `<path class="dist-arrow ${c}" d="M${x + 1},${y} l-5,-4 l0,8 z"/>`;
  parts.push(`<g class="kind-distance">`);
  if (activeCall) {
    const cx = xOf(activeCall.strike), dist = activeCall.strike - p.current, dp = (dist / p.current) * 100;
    const lineY = axisY - 12, x1 = Math.min(liveX, cx), x2 = Math.max(liveX, cx), midX = (liveX + cx) / 2;
    parts.push(`<line class="dist-line call" x1="${x1 + 5}" y1="${lineY}" x2="${x2 - 5}" y2="${lineY}" stroke-width="1"/>${arrowAt(x1, lineY, 'left', 'call')}${arrowAt(x2, lineY, 'right', 'call')}`);
    parts.push(`<text class="dist-label-text call" x="${midX}" y="${lineY - 8}" text-anchor="middle" font-family="DM Mono" font-size="10" letter-spacing=".4" font-weight="500" stroke="#061a10" stroke-width="3" stroke-linejoin="round" paint-order="stroke fill">${fmt$(dist)} · ${fmtPct(dp, 1)}</text>`);
  }
  if (activePut) {
    const px = xOf(activePut.strike), dist = activePut.strike - p.current, dp = (dist / p.current) * 100;
    const lineY = axisY + 12, x1 = Math.min(liveX, px), x2 = Math.max(liveX, px), midX = (liveX + px) / 2;
    parts.push(`<line class="dist-line put" x1="${x1 + 5}" y1="${lineY}" x2="${x2 - 5}" y2="${lineY}" stroke-width="1"/>${arrowAt(x1, lineY, 'left', 'put')}${arrowAt(x2, lineY, 'right', 'put')}`);
    parts.push(`<text class="dist-label-text put" x="${midX}" y="${lineY + 14}" text-anchor="middle" font-family="DM Mono" font-size="10" letter-spacing=".4" font-weight="500" stroke="#061a10" stroke-width="3" stroke-linejoin="round" paint-order="stroke fill">${fmt$(dist)} · ${fmtPct(dp, 1)}</text>`);
  }
  parts.push(`</g>`);

  // closes (tight band below axis)
  parts.push(`<g class="kind-closes">`);
  p.closes.forEach((cl, i) => {
    if (cl.price < min || cl.price > max) return;
    const x = xOf(cl.price), isToday = i === p.closes.length - 1;
    const jitter = ((i * 17) % 18) + 4, y = axisY + 30 + jitter, recency = i / p.closes.length;
    if (isToday) {
      parts.push(`<circle class="te" data-d="${cl.date}" cx="${x}" cy="${y}" r="3" fill="#d2e632"/><circle class="te" data-d="${cl.date}" cx="${x}" cy="${y}" r="7" fill="#d2e632" fill-opacity=".25"/>`);
    } else {
      parts.push(`<circle class="te" data-d="${cl.date}" cx="${x}" cy="${y}" r="1.6" fill="#468278" opacity="${(0.22 + recency * 0.55).toFixed(2)}"/>`);
    }
  });
  parts.push(`</g>`);

  // puts
  const putY = axisY + 60;
  p.puts.forEach((pu) => {
    const x = xOf(pu.strike), tip = esc(ttOption(pu, p, 'put'));
    const kindCls = pu.status === 'active' ? (pu.side === 'sold' ? 'kind-put-sold' : 'kind-put-bought') : 'kind-closed';
    const dd = pu.status === 'active' ? pu.bought : pu.closed;
    if (pu.status === 'active') {
      const tailH = Math.min(34, Math.max(16, pu.prem * 2.0));
      const strikeY = putY + 5 + tailH + 14, premY = strikeY + 13;
      const verb = pu.side === 'sold' ? 'PUT' : '+ PUT', sign = pu.side === 'sold' ? '+' : '−';
      parts.push(`<g class="${kindCls} te" data-d="${dd || ''}">
        <line x1="${x}" y1="${putY + 5}" x2="${x}" y2="${putY + 5 + tailH}" stroke="#e0c060" stroke-width="1.5"/>
        <circle class="armed-halo put" cx="${x}" cy="${putY}" r="12" fill="#e0c060"/>
        ${pu.side === 'sold'
          ? `<circle class="hot armed put" data-role="put-dot" cx="${x}" cy="${putY}" r="6" fill="#e0c060" data-tip="${tip}"/>`
          : `<circle class="hot armed put bought" data-role="put-dot" cx="${x}" cy="${putY}" r="7" fill="transparent" stroke="#e0c060" stroke-width="2" data-tip="${tip}"/>`}
        <text x="${x}" y="${strikeY}" text-anchor="middle" font-family="DM Mono" font-size="10" fill="#e0c060" letter-spacing="1px" font-weight="500" stroke="#061a10" stroke-width="3" stroke-linejoin="round" paint-order="stroke fill">${verb} $${pu.strike}</text>
        <text x="${x}" y="${premY}" text-anchor="middle" font-family="DM Mono" font-size="9" fill="#e0c060" fill-opacity=".75" letter-spacing="1px" stroke="#061a10" stroke-width="3" stroke-linejoin="round" paint-order="stroke fill">${sign}$${pu.prem.toFixed(2)}</text>
      </g>`);
    } else {
      parts.push(`<g class="${kindCls} te" data-d="${dd || ''}"><circle class="hot" cx="${x}" cy="${putY}" r="5" fill="transparent" stroke="#e0c060" stroke-width="1.5" opacity=".35" data-tip="${tip}"/></g>`);
    }
  });

  // live marker
  parts.push(`<g class="kind-live fx-keep">
    <circle class="live-halo" cx="${liveX}" cy="${axisY}" r="14" fill="#faf5f0" fill-opacity=".20"/>
    <line class="live-line" x1="${liveX}" y1="60" x2="${liveX}" y2="${H - 30}" stroke="#faf5f0" stroke-width="2"/>
    <circle class="hot live-dot-circle" cx="${liveX}" cy="${axisY}" r="5" fill="#faf5f0" data-tip="${esc(ttLive(p))}"/>
    <text x="${liveX}" y="54" text-anchor="middle" font-family="DM Mono" font-size="11" fill="#faf5f0" font-weight="600" letter-spacing=".4">$${p.current.toFixed(2)}</text>
  </g>`);

  return `<svg class="band-svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${parts.join('')}</svg>`;
}

/* ---- band-only chrome (the embed) ---- */
function renderBandOnly(p: BandPosition, opts: MountOpts) {
  const toolbar = opts.toolbar === false ? '' : `<div class="band-toolbar"><button class="pc-btn whatif" data-act="whatif">↔ What-if</button><button class="pc-btn note" data-act="note">+ Note</button></div>`;
  const scrub = opts.scrubber === false ? '' : `<div class="scrubber"><button class="play" title="Replay">▶</button><div class="track"><input type="range" min="0" max="100" value="100"></div><div class="date-read live">Live · <b>now</b></div></div>`;
  return `<div class="pcard pcard-bandonly" data-pos="${p.t}">
    ${toolbar}
    <div class="band-wrap">${renderBand(p)}<div class="band-overlay"><div class="wf-handle"><div class="wf-line"></div><div class="wf-grip"></div><div class="wf-readout"></div></div></div></div>
    ${scrub}
  </div>`;
}

/* ---- geometry for overlays ---- */
function leftPctOf(price: number, p: BandPosition) {
  const [min, max] = p.range;
  return ((padL + ((price - min) / (max - min)) * plotW) / W) * 100;
}
function priceFromClientX(clientX: number, wrap: HTMLElement, p: BandPosition) {
  const r = wrap.getBoundingClientRect();
  const f = (clientX - r.left) / r.width;
  const [min, max] = p.range;
  const price = min + ((f * W - padL) / plotW) * (max - min);
  return Math.max(min, Math.min(max, price));
}

/* ---- tooltip element (mounted inside .dash so tokens resolve) ---- */
function ensureTooltip(root: Element): HTMLElement {
  const host = root.closest('.dash') ?? document.body;
  let t = host.querySelector(':scope > .poslens-tooltip') as HTMLElement | null;
  if (!t) { t = document.createElement('div'); t.className = 'poslens-tooltip'; host.appendChild(t); }
  return t;
}

/* ---- wiring ---- */
function wireHover(card: HTMLElement) {
  const tip = ensureTooltip(card);
  card.querySelectorAll<HTMLElement>('.hot').forEach((el) => {
    let origR: string | null = null, keepNode: Element | null = null;
    const wrap = el.closest('.band-wrap');
    const svg = (el as unknown as SVGElement).ownerSVGElement;
    el.addEventListener('mouseenter', () => {
      tip.innerHTML = el.dataset.tip || ''; tip.classList.add('show');
      origR = el.getAttribute('r');
      if (origR != null) {
        const ring = el.getAttribute('fill') === 'transparent' || el.getAttribute('fill') === 'none';
        el.setAttribute('r', String(parseFloat(origR) + (ring ? 2 : 3)));
        if (ring) { el.setAttribute('data-osw', el.getAttribute('stroke-width') || '1.5'); el.setAttribute('stroke-width', '2.5'); }
      }
      el.style.opacity = '1';
      if (svg && wrap) {
        let n: Element | null = el; while (n && n.parentNode !== svg) n = n.parentNode as Element;
        if (n && n.classList) { keepNode = n; n.classList.add('focus-keep'); wrap.classList.add('focus-on'); }
      }
    });
    el.addEventListener('mousemove', (e) => {
      const pad = 16, r = tip.getBoundingClientRect(), vw = innerWidth, vh = innerHeight;
      let left = e.clientX + pad, top = e.clientY + pad;
      if (left + r.width > vw - 8) left = e.clientX - r.width - pad;
      if (top + r.height > vh - 8) top = e.clientY - r.height - pad;
      tip.style.left = Math.max(8, left) + 'px'; tip.style.top = Math.max(8, top) + 'px';
    });
    el.addEventListener('mouseleave', () => {
      tip.classList.remove('show');
      if (origR != null) el.setAttribute('r', origR);
      const osw = el.getAttribute('data-osw'); if (osw) el.setAttribute('stroke-width', osw);
      el.style.opacity = '';
      if (wrap) wrap.classList.remove('focus-on');
      if (keepNode) { keepNode.classList.remove('focus-keep'); keepNode = null; }
    });
  });
}

function wireWhatIf(card: HTMLElement, p: BandPosition) {
  const wrap = card.querySelector<HTMLElement>('.band-wrap');
  const handle = card.querySelector<HTMLElement>('.wf-handle');
  const grip = card.querySelector<HTMLElement>('.wf-grip');
  const readout = card.querySelector<HTMLElement>('.wf-readout');
  const btn = card.querySelector<HTMLElement>('[data-act="whatif"]');
  if (!wrap || !handle || !grip || !readout) return;
  let on = false;
  function update(price: number) {
    handle!.style.left = leftPctOf(price, p) + '%';
    const shareUpnl = (price - p.avgCost) * p.totalShares;
    const moveFromSpot = (price / p.current - 1) * 100;
    const ac = p.calls.find((c) => c.status === 'active'), ap = p.puts.find((c) => c.status === 'active');
    let rows = `<div class="r-px">if $${price.toFixed(2)}</div>`;
    rows += `<div class="r-row"><span class="k">Δ from spot</span><span class="v ${moveFromSpot >= 0 ? 'pos' : 'neg'}">${moveFromSpot >= 0 ? '+' : '−'}${Math.abs(moveFromSpot).toFixed(1)}%</span></div>`;
    rows += `<div class="r-row"><span class="k">Unrealized</span><span class="v ${shareUpnl >= 0 ? 'pos' : 'neg'}">${fmt$(shareUpnl, 0)}</span></div>`;
    if (ac) { const itm = price > ac.strike; rows += `<div class="r-row"><span class="k">Call ${ac.strike}</span><span class="v ${itm ? 'warn' : 'neon'}">${itm ? 'ITM ✕' : 'safe ✓'}</span></div>`; }
    if (ap) { const itm = price < ap.strike; rows += `<div class="r-row"><span class="k">Put ${ap.strike}</span><span class="v ${itm ? 'warn' : 'neon'}">${itm ? 'ITM ✓' : 'OTM'}</span></div>`; }
    readout!.innerHTML = rows;
  }
  update(p.current);
  const setOn = (v: boolean) => { on = v; handle!.classList.toggle('show', on); if (btn) btn.classList.toggle('on', on); };
  if (btn) btn.addEventListener('click', () => setOn(!on));
  let dragging = false;
  const moveToClient = (cx: number) => update(priceFromClientX(cx, wrap, p));
  grip.addEventListener('pointerdown', (e) => { if (!on) return; dragging = true; grip.setPointerCapture(e.pointerId); e.preventDefault(); });
  grip.addEventListener('pointermove', (e) => { if (dragging) moveToClient(e.clientX); });
  grip.addEventListener('pointerup', (e) => { dragging = false; try { grip.releasePointerCapture(e.pointerId); } catch { /* */ } });
  wrap.addEventListener('click', (e) => {
    if (!on || card.dataset.noteArm === '1') return;
    if ((e.target as Element).closest('.hot')) return;
    moveToClient(e.clientX);
  });
}

function wireAnnotations(card: HTMLElement, p: BandPosition) {
  const wrap = card.querySelector<HTMLElement>('.band-wrap');
  const overlay = card.querySelector<HTMLElement>('.band-overlay');
  const btn = card.querySelector<HTMLElement>('[data-act="note"]');
  if (!wrap || !overlay) return;
  const key = 'poslens.notes.' + p.t;
  const load = (): { price: number; text: string }[] => { try { return JSON.parse(localStorage.getItem(key) || '[]') || []; } catch { return []; } };
  const save = (arr: unknown) => { try { localStorage.setItem(key, JSON.stringify(arr)); } catch { /* */ } };
  function render() {
    overlay!.querySelectorAll('.note-pin').forEach((n) => n.remove());
    load().forEach((note, idx) => {
      const pin = document.createElement('div');
      pin.className = 'note-pin';
      pin.style.left = leftPctOf(note.price, p) + '%';
      pin.innerHTML = `<div class="np-line"></div><div class="np-flag" title="$${note.price.toFixed(2)} · ${note.text}">${note.text}<span class="np-x" data-i="${idx}">✕</span></div>`;
      overlay!.appendChild(pin);
    });
    overlay!.querySelectorAll<HTMLElement>('.np-x').forEach((x) => {
      x.addEventListener('click', (e) => { e.stopPropagation(); const arr = load(); arr.splice(+(x.dataset.i || 0), 1); save(arr); render(); });
    });
  }
  render();
  const arm = (v: boolean) => { card.dataset.noteArm = v ? '1' : ''; if (btn) btn.classList.toggle('on', v); wrap.classList.toggle('arming', v); };
  if (btn) btn.addEventListener('click', () => arm(card.dataset.noteArm !== '1'));
  wrap.addEventListener('click', (e) => {
    if (card.dataset.noteArm !== '1') return;
    if ((e.target as Element).closest('.np-flag') || (e.target as Element).closest('.note-input')) return;
    const price = priceFromClientX(e.clientX, wrap, p);
    overlay!.querySelectorAll('.note-input').forEach((n) => n.remove());
    const wrapIn = document.createElement('div');
    wrapIn.className = 'note-input';
    wrapIn.style.left = leftPctOf(price, p) + '%';
    wrapIn.innerHTML = `<input type="text" placeholder="note @ $${price.toFixed(2)}…" maxlength="40">`;
    overlay!.appendChild(wrapIn);
    const input = wrapIn.querySelector('input')!;
    input.focus();
    const commit = () => {
      const text = input.value.trim();
      if (text) { const arr = load(); arr.push({ price, text }); save(arr); }
      wrapIn.remove(); arm(false); render();
    };
    input.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') commit(); else if (ev.key === 'Escape') { wrapIn.remove(); arm(false); } });
    input.addEventListener('blur', () => { setTimeout(() => { if (document.body.contains(wrapIn)) commit(); }, 120); });
  });
}

function wireScrubber(card: HTMLElement) {
  const range = card.querySelector<HTMLInputElement>('.scrubber input[type=range]');
  const read = card.querySelector<HTMLElement>('.date-read');
  const play = card.querySelector<HTMLElement>('.play');
  if (!range || !read || !play) return;
  const tes = Array.from(card.querySelectorAll<HTMLElement>('.te'));
  const dates = tes.map((el) => parseD(el.dataset.d || '').getTime()).filter((n) => !isNaN(n));
  if (dates.length === 0) return;
  const earliest = Math.min(...dates), todayMs = parseD(todayIso()).getTime();
  function apply(val: number) {
    const threshold = earliest + (val / 100) * (todayMs - earliest);
    tes.forEach((el) => { const d = parseD(el.dataset.d || '').getTime(); el.style.display = (isNaN(d) || d <= threshold) ? '' : 'none'; });
    if (val >= 100) { read!.classList.add('live'); read!.innerHTML = 'Live · <b>now</b>'; }
    else { read!.classList.remove('live'); read!.innerHTML = 'As of <b>' + fmtDate(new Date(threshold)) + '</b>'; }
  }
  range.addEventListener('input', () => apply(+range.value));
  let playing = false, raf = 0;
  play.addEventListener('click', () => {
    if (playing) { playing = false; play!.textContent = '▶'; cancelAnimationFrame(raf); return; }
    playing = true; play!.textContent = '❚❚';
    range.value = '0'; apply(0);
    const start = performance.now(), dur = 5200;
    function step(now: number) {
      if (!playing) return;
      const t = Math.min(1, (now - start) / dur);
      range!.value = String(t * 100); apply(t * 100);
      if (t < 1) raf = requestAnimationFrame(step); else { playing = false; play!.textContent = '▶'; }
    }
    raf = requestAnimationFrame(step);
  });
}

/* ---- public API ---- */
export function mountBand(container: Element | string, pos: BandPosition, opts: MountOpts = {}): () => void {
  const el = typeof container === 'string' ? document.querySelector(container) : container;
  if (!el) { console.warn('mountBand: container not found'); return () => {}; }
  if (!pos) { console.warn('mountBand: no position data'); return () => {}; }
  const hidden = opts.hidden || CURATED_HIDDEN;
  el.innerHTML = renderBandOnly(pos, opts);
  const card = el.querySelector<HTMLElement>('[data-pos]');
  if (!card) return () => {};
  hidden.forEach((k) => card.classList.add('hide-' + k));
  wireHover(card);
  wireWhatIf(card, pos);
  wireAnnotations(card, pos);
  wireScrubber(card);
  return () => {
    // remove the tooltip we may have created in the .dash host
    const host = el.closest('.dash') ?? document.body;
    host.querySelectorAll(':scope > .poslens-tooltip').forEach((t) => t.remove());
    el.innerHTML = '';
  };
}
