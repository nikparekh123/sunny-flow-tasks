# Sunny position engine · notes for porting (from the Nov 6 handoff prototype)

Everything below is copied verbatim from the frozen prototype in `handoff-2026-11-06-home-positions/reference/` so the Swift engine can be ported line by line. Each block has one line on what it does, the inputs it reads, and its file and line range. Long one-line JS is kept as is (do not reformat when diffing against the source).

Read with README §9.2 (the engine) and §12 (invariants). Where the prototype and the README disagree, it is called out under **Differences to settle**.

## Inputs (the sample book, `sunny-web-data.js`)

| Name | What it is | Shape |
|---|---|---|
| `Q[t]` | price now and previous close | `[now, prevClose]` |
| `IV[t]` | one implied vol per name (no per-leg IV, no rate) | number, e.g. `.35` |
| `BOOK[t]` | the account's book (refilled by `useAcct('a' or 'b')`) | `{ st, sh: [shares, avgCost], sold: [[strike, 'c' or 'p', qty, soldAt, now]], legs: [[name, strike, qty, expiry, paid]], ld, decay }`; leg names `LEAPS`, `Hedge call` (= OTM calls), `Insurance put` |
| `BK` | the held names, in book order | `['BABA','LULU','NKE','NFLX','UBER','FIS','PEP']` |
| `XD[expiry]` | calendar days from Tue Oct 27 to each long expiry | `{ 'Jan 15': 80, 'Mar 19': 143, 'Jun ’27': 234, 'Sep ’27': 325, 'Jan ’28': 451 }` |
| `EXP` | every chain: `[name, calendar days left, kind, trading days]` | `['Oct 30', 3, 'Weekly', 5]` ... |
| `DIV[t]` / `divOf(t)` | dividends: per share, ex-date, days away | see below |
| sold legs `T` | this week's sold legs expire in 3 calendar days (Oct 30) | hard-coded `T: 3` |
| time offsets | `t0` = how far into today the moment is, in days: pre `a` 0, market `b` .3, post `c` .5, weekend `e` 4; `th` = Friday's close: 2.9 (weekend 9.9) | in `rv46` |


### Prices, IV, names

The quotes (now, previous close), one IV per name, company names, held names, watchlist and indexes.

**Inputs:** -  
**Source:** `reference/sunny-web-data.js` lines 3-7 (verbatim)

```js
  const Q = { SPY: [671.20, 668.52], QQQ: [610.40, 606.81], VIX: [16.40, 16.93], BABA: [99.63, 101.77], LULU: [99.05, 104.04], NKE: [35.28, 35.90], NFLX: [73.40, 72.10], UBER: [67.10, 67.85], FIS: [33.60, 33.95], PEP: [141.20, 140.60],
    MSFT: [512.30, 498.10], GOOGL: [242.11, 236.40], META: [731.20, 744.90], AMD: [164.72, 158.05], SHOP: [148.60, 141.22], COST: [918.40, 925.10], CRM: [244.80, 238.33], PLTR: [178.20, 171.95], DIS: [112.40, 115.02], SBUX: [86.10, 83.70] };
  const IV = { SPY: .15, QQQ: .2, VIX: .9, BABA: .40, LULU: .48, NKE: .35, NFLX: .45, UBER: .38, FIS: .30, PEP: .18, MSFT: .26, GOOGL: .30, META: .36, AMD: .50, SHOP: .55, COST: .20, CRM: .34, PLTR: .65, DIS: .28, SBUX: .30 };
  const CO = { SPY: 'S&P 500', QQQ: 'Nasdaq 100', VIX: 'Volatility', BABA: 'Alibaba', LULU: 'Lululemon', NKE: 'Nike', NFLX: 'Netflix', UBER: 'Uber', FIS: 'Fidelity National', PEP: 'PepsiCo', MSFT: 'Microsoft', GOOGL: 'Alphabet', META: 'Meta', AMD: 'AMD', SHOP: 'Shopify', COST: 'Costco', CRM: 'Salesforce', PLTR: 'Palantir', DIS: 'Disney', SBUX: 'Starbucks' };
  const BK = ['BABA', 'LULU', 'NKE', 'NFLX', 'UBER', 'FIS', 'PEP'], WL = ['MSFT', 'GOOGL', 'META', 'AMD', 'SHOP', 'COST', 'CRM', 'PLTR', 'DIS', 'SBUX'], IDX = ['SPY', 'QQQ', 'VIX'];
```

### The two books

Book a (Sunny) and book b (Nicolay). `sold` = this week's sold legs `[strike, side, qty, sold at, now]`; `sh` = `[shares, average cost]`; `legs` = `[name, strike, qty, expiry, paid]`.

**Inputs:** -  
**Source:** `reference/sunny-web-data.js` lines 8-27 (verbatim)

```js
  // Nov 5 (Nik): shares are the base, LEAPS only on some names · sold: [strike, side, qty, sold at, now] · sh: [shares, average cost] · legs: [name, strike, qty, expiry, paid] · 'Hedge call' = the OTM calls (5 to 10% out, 7 to 12 months; the key stays for older files) · one call sold per 100 shares, LEAPS are never sold against · ld = LEAPS delta, 0 without LEAPS · decay = a week of decay on the options bought
  // Nov 5 (Nik): two accounts, the app switches between them · a = Nik, b = his cousin (same playbook and names, smaller, LEAPS only on Netflix, no put selling but Nike) · BOOK, LEGS, TD, DIVP, INS, DG, LOG and BASE are refilled in place by useAcct(id), so every card reads the account on screen
  // Nov 6 (Nik): he sells a little more calls than shares cover, the rest against the OTM calls (NKE 72 on 6,000 shares + 20 OTM, BABA 20 on 1,500 + 10, NFLX 26 on 2,000 + 10)
  const BOOK_A = {
    BABA: { st: 'Aftershock', sh: [1500, 88.40], sold: [[104, 'c', 20, .66, .535]], legs: [['LEAPS', 100, 5, 'Jan ’28', 26.40], ['Hedge call', 108, 10, 'Sep ’27', 11.20], ['Insurance put', 95, 5, 'Jan 15', 4.90]], ld: .62, decay: 420 },
    LULU: { st: 'Rebound', sh: [1000, 118.20], sold: [], legs: [['LEAPS', 90, 10, 'Jan ’28', 24.80], ['Hedge call', 105, 6, 'Jun ’27', 12.90], ['Insurance put', 90, 5, 'Jan 15', 4.20]], ld: .71, decay: 390 },
    NKE: { st: 'Ladder', sh: [6000, 41.10], sold: [[36, 'c', 72, .32, .06], [34, 'p', 30, .18, .03]], legs: [['Hedge call', 38, 20, 'Sep ’27', 3.60], ['Insurance put', 33, 30, 'Mar 19', 1.45]], ld: 0, decay: 310 },
    NFLX: { st: '', sh: [2000, 61.50], sold: [[74, 'c', 26, .55, .30]], legs: [['LEAPS', 65, 10, 'Jan ’28', 19.20], ['Hedge call', 80, 10, 'Jun ’27', 8.40]], ld: .74, decay: 300 },
    UBER: { st: '', sh: [1200, 72.30], sold: [[71, 'c', 12, .40, .28]], legs: [], ld: 0, decay: 0 },
    FIS: { st: '', sh: [2500, 30.90], sold: [[35, 'c', 25, .20, .09]], legs: [], ld: 0, decay: 0 },
    PEP: { st: '', sh: [800, 152.60], sold: [[145, 'c', 8, .70, .51]], legs: [], ld: 0, decay: 0 } };
  const BOOK_B = {
    BABA: { st: 'Aftershock', sh: [500, 92.10], sold: [[104, 'c', 5, .66, .535]], legs: [['Insurance put', 95, 2, 'Jan 15', 4.90]], ld: 0, decay: 60 },
    LULU: { st: 'Rebound', sh: [400, 112.50], sold: [], legs: [['Hedge call', 105, 2, 'Jun ’27', 12.90]], ld: 0, decay: 80 },
    NKE: { st: 'Ladder', sh: [2000, 39.80], sold: [[36, 'c', 20, .32, .06]], legs: [['Insurance put', 33, 10, 'Mar 19', 1.45]], ld: 0, decay: 70 },
    NFLX: { st: '', sh: [600, 64.00], sold: [[74, 'c', 6, .55, .30]], legs: [['LEAPS', 65, 3, 'Jan ’28', 19.20], ['Hedge call', 80, 3, 'Jun ’27', 8.40]], ld: .74, decay: 110 },
    UBER: { st: '', sh: [500, 70.10], sold: [[71, 'c', 5, .40, .28]], legs: [], ld: 0, decay: 0 },
    FIS: { st: '', sh: [1000, 31.20], sold: [[35, 'c', 10, .20, .09]], legs: [], ld: 0, decay: 0 },
    PEP: { st: '', sh: [300, 150.10], sold: [[145, 'c', 3, .70, .51]], legs: [], ld: 0, decay: 0 } };
  const BOOK = {};
```

### Days to each long expiry (XD)

Calendar days from Tue Oct 27; legs not in the table use 300 in `rv46`.

**Inputs:** -  
**Source:** `reference/sunny-web-data.js` lines 28-29 (verbatim)

```js
  // days to each long expiry from Tue Oct 27
  const XD = { 'Jan 15': 80, 'Mar 19': 143, 'Jun ’27': 234, 'Sep ’27': 325, 'Jan ’28': 451 };
```

### Dividends and divOf

Per share, ex-date, days from Oct 27; `divOf(t)` adds the amount for the shares held (shares × per share).

**Inputs:** DIV, BOOK  
**Source:** `reference/sunny-web-data.js` lines 30-34 (verbatim)

```js
  // dividends (Nov 5, Nik; sample dates on each company's usual cycle): ps = per share, per = quarter or year, ex = next ex-date, d = days from Tue Oct 27, asg = the day before (calls sold in the money can be assigned), pay = pay date · LULU, NFLX and UBER pay none
  const DIV = { NKE: { ps: .41, per: 'quarter', ex: 'Tue Dec 1', d: 35, asg: 'Mon Nov 30', pay: 'Mon Jan 4' }, PEP: { ps: 1.4225, per: 'quarter', ex: 'Fri Dec 4', d: 38, asg: 'Thu Dec 3', pay: 'Wed Jan 6' }, FIS: { ps: .40, per: 'quarter', ex: 'Tue Dec 8', d: 42, asg: 'Mon Dec 7', pay: 'Tue Dec 22' }, BABA: { ps: 1.05, per: 'year', ex: 'Jun ’27', d: 225, asg: '', pay: 'Jul ’27' } };
  // what came in, newest first: [ticker, paid on, amount]
  const DIVP_A = [['NKE', 'Thu Oct 1', 2460], ['PEP', 'Wed Sep 30', 1138], ['FIS', 'Wed Sep 23', 1000]], DIVP_B = [['NKE', 'Thu Oct 1', 820], ['PEP', 'Wed Sep 30', 427], ['FIS', 'Wed Sep 23', 400]], DIVP = [];
  const divOf = t => { const d = DIV[t], b = BOOK[t]; if (!d || !b || !b.sh) return null; const n = d.per === 'year' ? 1 : 4; return Object.assign({ t, amt: Math.round(d.ps * b.sh[0]), yr: Math.round(d.ps * n * b.sh[0]), yld: d.ps * n / Q[t][0] }, d); };
```

### Yield and Payback base

What you bought: shares at cost plus what the LEAPS and OTM calls cost (insurance is a cost, not capital).

**Inputs:** BOOK  
**Source:** `reference/sunny-web-data.js` lines 35-36 (verbatim)

```js
  // Payback and yield base: everything bought, shares at cost plus what the LEAPS and OTM calls cost (insurance is a cost, not capital)
  const baseOf = B => Object.keys(B).reduce((a, t) => { const b = B[t]; return a + b.sh[0] * b.sh[1] + b.legs.filter(l => l[0] !== 'Insurance put').reduce((x, l) => x + l[2] * 100 * (l[4] || 0), 0); }, 0);
```

### Walls (weekly, Oct 30)

BABA, LULU, NKE by hand; every other name scales Nike's walls to its price.

**Inputs:** Q, W0  
**Source:** `reference/sunny-web-data.js` lines 37-43 (verbatim)

```js
  // Oct 30 weekly walls: [strike, side, label, confidence 1-3, gamma $M] · BABA, LULU, NKE by hand, the rest scale NKE's to their price
  const W0 = { BABA: { flip: 99.40, w: [[108, 'c', 'Ceiling', 2, 7.1], [104, 'c', 'Ceiling', 3, 12.4], [99, 'p', 'Accelerator', 2, 9.8], [98, 'p', 'Accelerator', 3, 6.2], [95, 'p', 'Unclear', 1, 3.4]] },
    LULU: { flip: 91.5, w: [[105, 'c', 'Ceiling', 2, 5.2], [100, 'c', 'Ceiling', 3, 8.9], [95, 'p', 'Floor', 2, 6.1], [92, 'p', 'Floor', 1, 3.0]] },
    NKE: { flip: 33.8, w: [[40, 'c', 'Unclear', 1, 2.1], [37.5, 'c', 'Ceiling', 2, 4.1], [36, 'c', 'Ceiling', 3, 6.3], [34, 'p', 'Floor', 2, 5.4], [33.5, 'p', 'Accelerator', 1, 3.2]] } };
  const WC = {};
  const walls = t => WC[t] || (WC[t] = W0[t] || (() => { const px = Q[t][0], r = px / 35.28, z = px < 50 ? .5 : px < 200 ? 1 : 5, rs = k => +(Math.round(k * r / z) * z).toFixed(2), seen = new Set();
    return { flip: +(W0.NKE.flip * r).toFixed(2), w: W0.NKE.w.map(([k, s, l, c, g]) => [rs(k), s, l, c, +(g * r).toFixed(1)]).filter(w => !seen.has(w[0]) && seen.add(w[0])) }; })());
```

### Priced move (sd)

The weekly priced move in % used by Home and the Positions dots: IV × √(5/252) × 100.

**Inputs:** IV  
**Source:** `reference/sunny-web-data.js` lines 44 (verbatim)

```js
  const sd = t => (IV[t] || .3) * Math.sqrt(5 / 252) * 100;
```

### Sold summary (kept, left, captured)

Per name: collected, left to buy back, kept, % captured and the pace tag.

**Inputs:** BOOK.sold  
**Source:** `reference/sunny-web-data.js` lines 75-76 (verbatim)

```js
  const soldSum = t => { const b = BOOK[t]; if (!b || !b.sold.length) return null; let col = 0, left = 0; b.sold.forEach(([k, s, q, p, n]) => { col += q * 100 * p; left += q * 100 * n; });
    const kept = col - left, cap = Math.round(kept / col * 100), pace = (1 - Math.sqrt(.6)) * 100; return { col, left, kept, cap, gone: 40, tag: cap >= pace + 5 ? 'Ahead' : cap <= pace - 5 ? 'Behind' : 'On pace' }; };
```

### Every chain (EXP) and netAt

Chains with calendar and trading days; `netAt(t, S)` = net delta in shares at price S today, held legs only (shares 1 each, LEAPS and OTM calls by Black-Scholes, To do left out).

**Inputs:** BOOK, IV, XD, EXP, LEGS  
**Source:** `reference/sunny-web-data.js` lines 127-128 (verbatim)

```js
  // Every chain (Oct 27, Web rounds 4 and 5) · EXP: [name, days left, kind, trading days] · chain(t, e) = { flip, c: Ceiling, f: Floor, a: Accelerator }, each [strike, confidence 1-3, gamma $M] or null · BABA, LULU, NKE by hand, the rest scale NKE's; Oct 30 matches W0
  const EXP = [['Oct 30', 3, 'Weekly', 5], ['Nov 6', 10, 'Weekly', 10], ['Nov 13', 17, 'Weekly', 15], ['Nov 20', 24, 'Monthly', 20], ['Dec 18', 52, 'Monthly', 40], ['Jan 15', 80, 'Monthly', 59], ['Mar 19', 143, 'Monthly', 102]];
```

### netAt helpers

Normal CDF, Black-Scholes delta and netAt.

**Inputs:** BOOK, IV, XD, EXP, LEGS  
**Source:** `reference/sunny-web-data.js` lines 154-162 (verbatim)

```js
  const NC = x => { const z = Math.abs(x) / Math.SQRT2, u = 1 / (1 + .3275911 * z), y = 1 - ((((1.061405429 * u - 1.453152027) * u + 1.421413741) * u - .284496736) * u + .254829592) * u * Math.exp(-z * z); return .5 * (1 + (x >= 0 ? y : -y)); };
  const bsd = (S, k, T, iv, put) => NC((Math.log(S / k) + iv * iv * T / 2) / (iv * Math.sqrt(T))) - (put ? 1 : 0);
  // net delta in shares if the price were S today (held legs only, To do left out) · returns [net, long delta] · shares count one each, LEAPS and OTM calls by Black-Scholes
  const netAt = (t, S) => { const b = BOOK[t], iv = IV[t] || .3; if (!b) return null; let n = 0, lng = 0;
    if (b.sh) { n += b.sh[0]; lng += b.sh[0]; }
    b.legs.forEach(l => { if (l[0] === 'Insurance put' || !XD[l[3]] || XD[l[3]] < 200) return; const x = l[2] * 100 * bsd(S, l[1], XD[l[3]] / 365, iv); n += x; lng += x; });
    (LEGS[t] || []).forEach(([, s, k, q, e, kind]) => { if (kind === 't') return; const x = q * 100 * bsd(S, k, EXP[e][1] / 365, iv, s === 'p'); if (kind === 's') n -= x; else { n += x; if (s === 'c') lng += x; } });
    return [n, lng]; };
  const CH = { EXP, chain, ERN, LEGS, WAS, netAt };
```

## Home · Your position (`SunnyBriefs.dc.html`, `rv46`)

One function builds the whole card. It is shown in full first, then each piece is called out below with its line.


### rv46 in full

The Your position card: P&L by % move for the whole book, the sentence, the three numbers, the cover line, early assignment, the By name rows and the chart paths.

**Inputs:** BOOK, BK, Q, IV, XD, sd, divOf; props.clock (a pre, b market, c post, e weekend)  
**Source:** `reference/SunnyBriefs.dc.html` lines 1035-1072 (verbatim)

```js
  rv46() { const D = window.SunnyWebData, E = { p46: { story: [], stats: [], rows: [], area: 'M0 0', line: 'M0 0', now: 'M0 0' } }; if (!D || !D.BOOK || !D.Q || this.props.only !== 'pos') return E;
    const ck = this.props.clock || 'a', wk = ck === 'e', t0 = { a: 0, b: .3, c: .5, e: 4 }[ck] ?? 0, th = wk ? 9.9 : 2.9, XD = Object.assign({ 'Jan 15': 80, 'Mar 19': 143, 'Jun ’27': 234, 'Sep ’27': 325, 'Jan ’28': 451 }, D.XD || {});
    const erf = x => { const g = Math.sign(x), a = Math.abs(x), q = 1 / (1 + .3275911 * a); return g * (1 - (((((1.061405429 * q - 1.453152027) * q) + 1.421413741) * q - .284496736) * q + .254829592) * q * Math.exp(-a * a)); }, N = x => .5 * (1 + erf(x / Math.SQRT2));
    const bs = (S, K, T, v, put) => { if (T <= 0) return put ? Math.max(K - S, 0) : Math.max(S - K, 0); const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + v * v / 2 * T) / sq, c = S * N(d1) - K * N(d1 - sq); return put ? c - S + K : c; };
    const dl = (S, K, T, v, put) => { const TT = Math.max(T, .02 / 365), d1 = (Math.log(S / K) + v * v / 2 * TT) / (v * Math.sqrt(TT)); return N(d1) - (put ? 1 : 0); };
    const BK = (D.BK || []).filter(t => D.BOOK[t]), CO = { BABA: 'Alibaba', LULU: 'Lululemon', NKE: 'Nike', NFLX: 'Netflix', UBER: 'Uber', FIS: 'FIS', PEP: 'PepsiCo' };
    const legs = t => { const b = D.BOOK[t], o = []; if (b.sh) o.push({ ty: 'S', q: b.sh[0] }); if (!wk) b.sold.forEach(([K, s2, q]) => o.push({ ty: s2 === 'c' ? 'C' : 'P', K, q: -q, T: 3 })); b.legs.forEach(([nm, K, q, ex]) => o.push({ ty: nm === 'Insurance put' ? 'P' : 'C', K, q, T: XD[ex] || 300 })); return o; };
    const NB = BK.map(t => { const S0 = D.Q[t][0], v = D.IV[t] || .35, L = legs(t), val = (l, S, tt) => l.ty === 'S' ? l.q * S : l.q * 100 * bs(S, l.K, Math.max(0, l.T - tt) / 365, v, l.ty === 'P'), dt = (l, S, tt) => l.ty === 'S' ? l.q : l.q * 100 * dl(S, l.K, Math.max(0, l.T - tt) / 365, v, l.ty === 'P');
      const at = (m, tt) => { const S = S0 * (1 + m / 100); let p = 0, n = 0, lg = 0; L.forEach(l => { p += val(l, S, tt) - val(l, S0, t0); const x = dt(l, S, tt); n += x; if (l.q > 0 && l.ty !== 'P') lg += x; }); return { p, n, lg }; };
      return { t, S0, sd: D.sd ? D.sd(t) : 3, at }; });
    const M = []; for (let m = -10; m <= 10.001; m += .25) M.push(+m.toFixed(2));
    const bk = (m, tt) => NB.reduce((a, x) => { const r = x.at(m, tt); return { p: a.p + r.p, n: a.n + r.n, d$: a.d$ + r.n * x.S0 * (1 + m / 100) / 100 }; }, { p: 0, n: 0, d$: 0 });
    const F = M.map(m => bk(m, th)), Nw = M.map(m => bk(m, t0)), all = F.concat(Nw).map(r => r.p), mx = Math.max(...all, 1) * 1.1, mn = Math.min(...all, -1) * 1.1, W = 313, H = 150;
    const X = m => (m + 10) / 20 * W, Y = p => (mx - p) / (mx - mn) * H, pth = A => A.map((r, i) => (i ? 'L' : 'M') + X(M[i]).toFixed(1) + ' ' + Y(r.p).toFixed(1)).join(' ');
    const fi = M.findIndex((m, i) => m > 0 && F[i].n < 0), fm = fi >= 0 ? M[fi] : null, i0 = M.indexOf(0), now = bk(0, t0), y0 = Y(0);
    const f$ = x => '$' + Math.round(Math.abs(x)).toLocaleString('en-US'), fK = x => { const a = Math.abs(x); return a >= 1e4 ? '$' + Math.round(a / 1000) + 'K' : a >= 1000 ? '$' + (a / 1000).toFixed(1) + 'K' : '$' + Math.round(a); }, fn = x => Math.round(Math.abs(x)).toLocaleString('en-US'), f1 = x => (Math.round(x * 10) / 10).toFixed(1);
    const rows = NB.map(x => { const r = x.at(x.sd, th), thin = r.n >= 0 && r.n < .25 * r.lg, short = r.n < 0; let fp = null; for (let m = 0; m <= x.sd * 3; m += .05) { if (x.at(m, th).n < 0) { fp = x.S0 * (1 + m / 100); break; } }
      const st = short ? 2 : thin ? 1 : 0, c = short ? 'var(--rd)' : thin ? 'var(--or)' : 'var(--ink)';
      return { k: x.t, t: x.t, fp, st, frac: r.lg ? r.n / r.lg : 1, logo: 'assets/logos/' + x.t + '.png', name: CO[x.t] || x.t, sub: fp ? 'Short above $' + fp.toFixed(2) + ' by ' + (wk ? 'next Friday' : 'Friday') : thin ? 'Thin by Friday, never short' : 'Stays long past ↑' + f1(x.sd * 3) + '%', sc: fp ? (short ? 'var(--rd)' : 'var(--or)') : 'var(--mu)', v: short ? 'Short ' + fn(r.n) + ' Δ' : thin ? 'Thin' : 'Long ' + fn(r.n) + ' Δ', c, at: 'at ↑' + f1(x.sd) + '%', go: (this._pg46 || (this._pg46 = {}))[x.t] || (this._pg46[x.t] = () => { if (this.props.onPos) this.props.onPos(x.t); }), a: (CO[x.t] || x.t) + ': ' + (short ? 'short' : thin ? 'thin' : 'long') + ' if it rises ' + f1(x.sd) + '% by Friday. Open in Positions' }; })
      .sort((a, b) => b.st - a.st || a.frac - b.frac);
    rows.forEach((r, i) => { r.bt = i ? '1px solid var(--line)' : 'none'; });
    const nS = rows.filter(r => r.st === 2).length, nT = rows.filter(r => r.st === 1).length, first = rows.find(r => r.st > 0), sp = (t, fw, c) => ({ t, fw: fw || 500, c: c || 'var(--ink)' });
    const story = wk ? [sp('This week’s calls ended Friday, so you are '), sp('long only', 700), sp(' until Monday’s sales: a 1% rise makes you '), sp(fK(now.d$), 700, 'var(--gr)'), sp('. Selling again brings the short back above the calls.')]
      : [sp('Long now: a 1% rise makes you '), sp(fK(now.d$), 700, 'var(--gr)'), sp('. ')].concat(fm != null ? [sp('If the market rises '), sp(f1(fm) + '%', 700, 'var(--or)'), sp(' by Friday you turn short' + (first ? ', first in ' + first.name + '.' : '.'))] : [sp('The book stays long even if the market rises 10% by Friday')].concat(first ? [sp(', but '), sp(first.name, 700, first.st === 2 ? 'var(--rd)' : 'var(--or)'), sp(first.st === 2 && first.fp ? ' turns short above $' + first.fp.toFixed(2) + '.' : ' runs thin.')] : [sp('.')]));
    story.forEach((x, i) => { x.k = 's' + i; });
    const pv = F[i0].p, up5 = F[M.indexOf(5)].p, dn5 = F[M.indexOf(-5)].p;
    let shT = 0, cvT = 0; BK.forEach(t => { const bb = D.BOOK[t], n = bb.sh ? bb.sh[0] : 0, I = bb.legs.find(l => l[0] === 'Insurance put'); shT += n; cvT += I ? Math.min(n, I[2] * 100) : 0; });
    const cov = 'Insurance puts cover ' + cvT.toLocaleString('en-US') + ' of your ' + shT.toLocaleString('en-US') + ' shares, ' + Math.round(cvT / Math.max(1, shT) * 100) + '%. Shares have no floor below that.';
    const exw = BK.map(t => D.divOf ? D.divOf(t) : null).filter(x => x && x.d <= 7 && D.BOOK[x.t].sold.some(y => y[1] === 'c'));
    const asg = exw.length ? 'Ex-dividend this week: ' + exw.map(x => (CO[x.t] || x.t) + ' ' + x.ex).join(', ') + '. Calls in the money with less time value than the dividend can be assigned the day before.' : '';
    const sub = { a: 'Before the bell · by Friday’s close', b: 'Now · by Friday’s close', c: 'At the close · by Friday', e: 'Calls ended Friday · to next Friday' }[ck];
    const line = pth(F);
    return { p46: { cov, asg, hasAsg: !!asg, sub, story, line, area: line + ' L' + W + ' ' + y0.toFixed(1) + ' L0 ' + y0.toFixed(1) + ' Z', now: pth(Nw), y0: y0.toFixed(1), cU: (y0 + 30).toFixed(1), id: 'p46' + ck, uId: 'url(#p46u' + ck + ')', dId: 'url(#p46d' + ck + ')', uK: 'p46u' + ck, dK: 'p46d' + ck,
      dx: X(0).toFixed(1), dy: Y(pv).toFixed(1), fx: fm != null ? X(fm).toFixed(1) : '-40', fO: fm != null ? 1 : 0, fl: fm != null ? 'Short above ↑' + f1(fm) + '%' : '', fL: fm != null ? X(fm).toFixed(1) + 'px' : '0px', fTx: fm != null && X(fm) > 220 ? '-100%' : '0%',
      stats: [{ k: 'u', v: (up5 < 0 ? '' : '') + fK(up5), c: up5 < 0 ? 'var(--rd)' : 'var(--gr)', l: 'if up 5%' }, { k: 'f', v: fK(pv), c: pv < 0 ? 'var(--rd)' : 'var(--gr)', l: wk ? 'flat to next Fri' : 'flat to Friday' }, { k: 'd', v: fK(dn5), c: dn5 < 0 ? 'var(--rd)' : 'var(--gr)', l: 'if down 5%' }],
      cnt: nS || nT ? (nS ? nS + ' short' : '') + (nS && nT ? ', ' : '') + (nT ? nT + ' thin' : '') + ' at a priced move' : 'Every name long at a priced move', cntC: nS ? 'var(--rd)' : nT ? 'var(--or)' : 'var(--mu)', rows,
      aria: 'Your position, P&L by ' + (wk ? 'next Friday' : 'Friday') + ' if the market moves 10% down to 10% up. ' + (fm != null ? 'Short above a ' + f1(fm) + '% rise.' : 'Long throughout.'),
      open: this._po46 || (this._po46 = () => { if (this.props.onPos) this.props.onPos(null); }) } };
```

### Moment clock and Friday

`t0` = days into today at this moment; `th` = days to Friday's close (2.9; weekend 9.9 = next Friday); `wk` = weekend (this week's sold legs are left out).

**Inputs:** props.clock  
**Source:** `reference/SunnyBriefs.dc.html` lines 1036 (verbatim)

```js
    const ck = this.props.clock || 'a', wk = ck === 'e', t0 = { a: 0, b: .3, c: .5, e: 4 }[ck] ?? 0, th = wk ? 9.9 : 2.9, XD = Object.assign({ 'Jan 15': 80, 'Mar 19': 143, 'Jun ’27': 234, 'Sep ’27': 325, 'Jan ’28': 451 }, D.XD || {});
```

### Black-Scholes helpers

erf (Abramowitz-Stegun 7.1.26), N(x), the call/put price with no rate and no dividend, and delta with a floor of .02 days so expiry does not divide by zero.

**Inputs:** S, K, T (years), v (IV)  
**Source:** `reference/SunnyBriefs.dc.html` lines 1037-1039 (verbatim)

```js
    const erf = x => { const g = Math.sign(x), a = Math.abs(x), q = 1 / (1 + .3275911 * a); return g * (1 - (((((1.061405429 * q - 1.453152027) * q) + 1.421413741) * q - .284496736) * q + .254829592) * q * Math.exp(-a * a)); }, N = x => .5 * (1 + erf(x / Math.SQRT2));
    const bs = (S, K, T, v, put) => { if (T <= 0) return put ? Math.max(K - S, 0) : Math.max(S - K, 0); const sq = v * Math.sqrt(T), d1 = (Math.log(S / K) + v * v / 2 * T) / sq, c = S * N(d1) - K * N(d1 - sq); return put ? c - S + K : c; };
    const dl = (S, K, T, v, put) => { const TT = Math.max(T, .02 / 365), d1 = (Math.log(S / K) + v * v / 2 * TT) / (v * Math.sqrt(TT)); return N(d1) - (put ? 1 : 0); };
```

### Legs per name

Shares (q = shares), this week's sold calls/puts (q negative, T = 3 days; dropped on the weekend), and the long legs (LEAPS and OTM calls as calls, Insurance put as put) with T from XD (300 if unknown).

**Inputs:** BOOK, XD  
**Source:** `reference/SunnyBriefs.dc.html` lines 1041 (verbatim)

```js
    const legs = t => { const b = D.BOOK[t], o = []; if (b.sh) o.push({ ty: 'S', q: b.sh[0] }); if (!wk) b.sold.forEach(([K, s2, q]) => o.push({ ty: s2 === 'c' ? 'C' : 'P', K, q: -q, T: 3 })); b.legs.forEach(([nm, K, q, ex]) => o.push({ ty: nm === 'Insurance put' ? 'P' : 'C', K, q, T: XD[ex] || 300 })); return o; };
```

### P&L and net delta at a % move and a date

`at(m, tt)`: move the name by m %, value every leg at `tt` days from now, P&L = value then minus value at `t0` (now); `n` = net delta in shares (sold legs negative, puts with put delta); `lg` = long delta (shares + bought calls).

**Inputs:** S0 = Q[t][0], v = IV[t] (.35 default), legs  
**Source:** `reference/SunnyBriefs.dc.html` lines 1042-1044 (verbatim)

```js
    const NB = BK.map(t => { const S0 = D.Q[t][0], v = D.IV[t] || .35, L = legs(t), val = (l, S, tt) => l.ty === 'S' ? l.q * S : l.q * 100 * bs(S, l.K, Math.max(0, l.T - tt) / 365, v, l.ty === 'P'), dt = (l, S, tt) => l.ty === 'S' ? l.q : l.q * 100 * dl(S, l.K, Math.max(0, l.T - tt) / 365, v, l.ty === 'P');
      const at = (m, tt) => { const S = S0 * (1 + m / 100); let p = 0, n = 0, lg = 0; L.forEach(l => { p += val(l, S, tt) - val(l, S0, t0); const x = dt(l, S, tt); n += x; if (l.q > 0 && l.ty !== 'P') lg += x; }); return { p, n, lg }; };
      return { t, S0, sd: D.sd ? D.sd(t) : 3, at }; });
```

### The x grid and the whole book

Every name moved by the same %, from −10% to +10% in .25 steps; `bk(m, tt)` sums P&L, net delta and dollar delta (`d$` = Σ n × price / 100, the $ per 1% move).

**Inputs:** NB  
**Source:** `reference/SunnyBriefs.dc.html` lines 1045-1046 (verbatim)

```js
    const M = []; for (let m = -10; m <= 10.001; m += .25) M.push(+m.toFixed(2));
    const bk = (m, tt) => NB.reduce((a, x) => { const r = x.at(m, tt); return { p: a.p + r.p, n: a.n + r.n, d$: a.d$ + r.n * x.S0 * (1 + m / 100) / 100 }; }, { p: 0, n: 0, d$: 0 });
```

### Your position chart

`F` = by Friday's close (solid), `Nw` = today (dashed). Y range ±10% padded; W 313, H 150. X(m) maps −10..10 to 0..W.

**Inputs:** NB  
**Source:** `reference/SunnyBriefs.dc.html` lines 1047-1048 (verbatim)

```js
    const F = M.map(m => bk(m, th)), Nw = M.map(m => bk(m, t0)), all = F.concat(Nw).map(r => r.p), mx = Math.max(...all, 1) * 1.1, mn = Math.min(...all, -1) * 1.1, W = 313, H = 150;
    const X = m => (m + 10) / 20 * W, Y = p => (mx - p) / (mx - mn) * H, pth = A => A.map((r, i) => (i ? 'L' : 'M') + X(M[i]).toFixed(1) + ' ' + Y(r.p).toFixed(1)).join(' ');
```

### Book turns short (orange line)

First move above 0 on the .25 grid where Friday's net delta is below zero; drawn only if inside +10%.

**Inputs:** F  
**Source:** `reference/SunnyBriefs.dc.html` lines 1049 (verbatim)

```js
    const fi = M.findIndex((m, i) => m > 0 && F[i].n < 0), fm = fi >= 0 ? M[fi] : null, i0 = M.indexOf(0), now = bk(0, t0), y0 = Y(0);
```

### Money format

`f$` whole dollars; `fK` $9.4K under $10K, $40K at $10K and over; `f1` one decimal.

**Inputs:** -  
**Source:** `reference/SunnyBriefs.dc.html` lines 1050 (verbatim)

```js
    const f$ = x => '$' + Math.round(Math.abs(x)).toLocaleString('en-US'), fK = x => { const a = Math.abs(x); return a >= 1e4 ? '$' + Math.round(a / 1000) + 'K' : a >= 1000 ? '$' + (a / 1000).toFixed(1) + 'K' : '$' + Math.round(a); }, fn = x => Math.round(Math.abs(x)).toLocaleString('en-US'), f1 = x => (Math.round(x * 10) / 10).toFixed(1);
```

### By name rows: thin, short, turns short to the cent, priced move

For each name at its own priced move up (`sd` = IV × √(5/252) × 100) by Friday: short = net delta < 0; thin = net delta ≥ 0 and < 25% of long delta. `fp` = first price where Friday's net delta < 0, searching 0 to 3 × sd in .05% steps of the name's move (so "to the cent" is only as fine as .05% of the price; the Positions flip below searches 400 steps). Row line: "Short above $fp by Friday" / "Thin by Friday, never short" / "Stays long past ↑(3 × sd)%". Right: "Short 917 Δ" / "Thin" / "Long 1,134 Δ" with "at ↑sd%". Sorted short, thin, long, then by net/long fraction.

**Inputs:** NB, sd  
**Source:** `reference/SunnyBriefs.dc.html` lines 1051-1056 (verbatim)

```js
    const rows = NB.map(x => { const r = x.at(x.sd, th), thin = r.n >= 0 && r.n < .25 * r.lg, short = r.n < 0; let fp = null; for (let m = 0; m <= x.sd * 3; m += .05) { if (x.at(m, th).n < 0) { fp = x.S0 * (1 + m / 100); break; } }
      const st = short ? 2 : thin ? 1 : 0, c = short ? 'var(--rd)' : thin ? 'var(--or)' : 'var(--ink)';
      return { k: x.t, t: x.t, fp, st, frac: r.lg ? r.n / r.lg : 1, logo: 'assets/logos/' + x.t + '.png', name: CO[x.t] || x.t, sub: fp ? 'Short above $' + fp.toFixed(2) + ' by ' + (wk ? 'next Friday' : 'Friday') : thin ? 'Thin by Friday, never short' : 'Stays long past ↑' + f1(x.sd * 3) + '%', sc: fp ? (short ? 'var(--rd)' : 'var(--or)') : 'var(--mu)', v: short ? 'Short ' + fn(r.n) + ' Δ' : thin ? 'Thin' : 'Long ' + fn(r.n) + ' Δ', c, at: 'at ↑' + f1(x.sd) + '%', go: (this._pg46 || (this._pg46 = {}))[x.t] || (this._pg46[x.t] = () => { if (this.props.onPos) this.props.onPos(x.t); }), a: (CO[x.t] || x.t) + ': ' + (short ? 'short' : thin ? 'thin' : 'long') + ' if it rises ' + f1(x.sd) + '% by Friday. Open in Positions' }; })
      .sort((a, b) => b.st - a.st || a.frac - b.frac);
    rows.forEach((r, i) => { r.bt = i ? '1px solid var(--line)' : 'none'; });
    const nS = rows.filter(r => r.st === 2).length, nT = rows.filter(r => r.st === 1).length, first = rows.find(r => r.st > 0), sp = (t, fw, c) => ({ t, fw: fw || 500, c: c || 'var(--ink)' });
```

### The sentence

Long now: "a 1% rise makes you" = `fK(now.d$)` where `now = bk(0, t0)` (dollar delta today, not P&L(+1%) − P&L(0)). Then either the book turns short at fm %, or "stays long even if the market rises 10% by Friday, but {first short or thin name} turns short above $fp" (first = first row after sorting). Weekend text is fixed.

**Inputs:** rows, now, fm  
**Source:** `reference/SunnyBriefs.dc.html` lines 1056-1059 (verbatim)

```js
    const nS = rows.filter(r => r.st === 2).length, nT = rows.filter(r => r.st === 1).length, first = rows.find(r => r.st > 0), sp = (t, fw, c) => ({ t, fw: fw || 500, c: c || 'var(--ink)' });
    const story = wk ? [sp('This week’s calls ended Friday, so you are '), sp('long only', 700), sp(' until Monday’s sales: a 1% rise makes you '), sp(fK(now.d$), 700, 'var(--gr)'), sp('. Selling again brings the short back above the calls.')]
      : [sp('Long now: a 1% rise makes you '), sp(fK(now.d$), 700, 'var(--gr)'), sp('. ')].concat(fm != null ? [sp('If the market rises '), sp(f1(fm) + '%', 700, 'var(--or)'), sp(' by Friday you turn short' + (first ? ', first in ' + first.name + '.' : '.'))] : [sp('The book stays long even if the market rises 10% by Friday')].concat(first ? [sp(', but '), sp(first.name, 700, first.st === 2 ? 'var(--rd)' : 'var(--or)'), sp(first.st === 2 && first.fp ? ' turns short above $' + first.fp.toFixed(2) + '.' : ' runs thin.')] : [sp('.')]));
    story.forEach((x, i) => { x.k = 's' + i; });
```

### The three numbers

P&L by Friday at +5%, at 0% ("flat to Friday"; weekend "flat to next Fri") and at −5%, from `F`. Includes this week's premium already earned because P&L is measured from now with the sold legs' current marks.

**Inputs:** F  
**Source:** `reference/SunnyBriefs.dc.html` lines 1060 (verbatim)

```js
    const pv = F[i0].p, up5 = F[M.indexOf(5)].p, dn5 = F[M.indexOf(-5)].p;
```

### Put cover line

Σ min(shares, insurance puts × 100) over Σ shares, rounded %.

**Inputs:** BOOK  
**Source:** `reference/SunnyBriefs.dc.html` lines 1061-1062 (verbatim)

```js
    let shT = 0, cvT = 0; BK.forEach(t => { const bb = D.BOOK[t], n = bb.sh ? bb.sh[0] : 0, I = bb.legs.find(l => l[0] === 'Insurance put'); shT += n; cvT += I ? Math.min(n, I[2] * 100) : 0; });
    const cov = 'Insurance puts cover ' + cvT.toLocaleString('en-US') + ' of your ' + shT.toLocaleString('en-US') + ' shares, ' + Math.round(cvT / Math.max(1, shT) * 100) + '%. Shares have no floor below that.';
```

### Early assignment line

Ex-dividend within 7 days on a name with calls sold.

**Inputs:** divOf, BOOK.sold  
**Source:** `reference/SunnyBriefs.dc.html` lines 1063-1064 (verbatim)

```js
    const exw = BK.map(t => D.divOf ? D.divOf(t) : null).filter(x => x && x.d <= 7 && D.BOOK[x.t].sold.some(y => y[1] === 'c'));
    const asg = exw.length ? 'Ex-dividend this week: ' + exw.map(x => (CO[x.t] || x.t) + ' ' + x.ex).join(', ') + '. Calls in the money with less time value than the dividend can be assigned the day before.' : '';
```

### Subtitle and outputs

Subtitle by moment; stats; the By name header ("1 short, 2 thin at a priced move" or "Every name long at a priced move"); the VoiceOver summary.

**Inputs:** -  
**Source:** `reference/SunnyBriefs.dc.html` lines 1065-1072 (verbatim)

```js
    const sub = { a: 'Before the bell · by Friday’s close', b: 'Now · by Friday’s close', c: 'At the close · by Friday', e: 'Calls ended Friday · to next Friday' }[ck];
    const line = pth(F);
    return { p46: { cov, asg, hasAsg: !!asg, sub, story, line, area: line + ' L' + W + ' ' + y0.toFixed(1) + ' L0 ' + y0.toFixed(1) + ' Z', now: pth(Nw), y0: y0.toFixed(1), cU: (y0 + 30).toFixed(1), id: 'p46' + ck, uId: 'url(#p46u' + ck + ')', dId: 'url(#p46d' + ck + ')', uK: 'p46u' + ck, dK: 'p46d' + ck,
      dx: X(0).toFixed(1), dy: Y(pv).toFixed(1), fx: fm != null ? X(fm).toFixed(1) : '-40', fO: fm != null ? 1 : 0, fl: fm != null ? 'Short above ↑' + f1(fm) + '%' : '', fL: fm != null ? X(fm).toFixed(1) + 'px' : '0px', fTx: fm != null && X(fm) > 220 ? '-100%' : '0%',
      stats: [{ k: 'u', v: (up5 < 0 ? '' : '') + fK(up5), c: up5 < 0 ? 'var(--rd)' : 'var(--gr)', l: 'if up 5%' }, { k: 'f', v: fK(pv), c: pv < 0 ? 'var(--rd)' : 'var(--gr)', l: wk ? 'flat to next Fri' : 'flat to Friday' }, { k: 'd', v: fK(dn5), c: dn5 < 0 ? 'var(--rd)' : 'var(--gr)', l: 'if down 5%' }],
      cnt: nS || nT ? (nS ? nS + ' short' : '') + (nS && nT ? ', ' : '') + (nT ? nT + ' thin' : '') + ' at a priced move' : 'Every name long at a priced move', cntC: nS ? 'var(--rd)' : nT ? 'var(--or)' : 'var(--mu)', rows,
      aria: 'Your position, P&L by ' + (wk ? 'next Friday' : 'Friday') + ' if the market moves 10% down to 10% up. ' + (fm != null ? 'Short above a ' + f1(fm) + '% rise.' : 'Long throughout.'),
      open: this._po46 || (this._po46 = () => { if (this.props.onPos) this.props.onPos(null); }) } };
```

## Positions chart (`SunnyPositions.dc.html`, `m45` model and `pay45` view)


### m45 in full (the per-name model)

Per name: legs, P&L and delta at any price S and date tt, the date slider stops, the price grid, turns-short search (`flip`), Greeks (`gk`), axis, technicals and walls in range.

**Inputs:** BOOK, Q, IV, XD, series, walls  
**Source:** `reference/SunnyPositions.dc.html` lines 402-427 (verbatim)

```js
  m45(t) { const W0 = window.SunnyWebData, ck = W0 ? W0.acct + ':' + W0.ver : ''; if (this._k45v !== ck) { this._k45 = {}; this._k45v = ck; } const C = this._k45; if (C[t]) return C[t]; const D = window.SunnyWebData; if (!D || !D.BOOK || !D.BOOK[t] || !D.walls || !D.series) return null;
    const b = D.BOOK[t], S0 = D.Q[t][0], P0 = D.Q[t][1], v = D.IV[t] || .35, XD = Object.assign({ 'Jan 15': 80, 'Mar 19': 143, 'Jun ’27': 234, 'Sep ’27': 325, 'Jan ’28': 451 }, D.XD || {}), W = 353, H = 190, X0 = S0 * .88, X1 = S0 * 1.12, n0 = x => x.toLocaleString('en-US');
    const erf = x => { const sg = Math.sign(x), a = Math.abs(x), q = 1 / (1 + .3275911 * a); return sg * (1 - (((((1.061405429 * q - 1.453152027) * q) + 1.421413741) * q - .284496736) * q + .254829592) * q * Math.exp(-a * a)); };
    const Nn = x => .5 * (1 + erf(x / Math.SQRT2)), bsV = (S, K, T, put, vv) => { if (T <= 0) return put ? Math.max(K - S, 0) : Math.max(S - K, 0); const sq = vv * Math.sqrt(T), d1 = (Math.log(S / K) + vv * vv / 2 * T) / sq, c = S * Nn(d1) - K * Nn(d1 - sq); return put ? c - S + K : c; };
    const bs = (S, K, T, put) => bsV(S, K, T, put, v), dl = (S, K, T, put) => { const TT = Math.max(T, .02 / 365), d1 = (Math.log(S / K) + v * v / 2 * TT) / (v * Math.sqrt(TT)); return Nn(d1) - (put ? 1 : 0); };
    const fk = k => (k % 1 ? String(+k.toFixed(2)) : String(k)), NM = { LEAPS: 'LEAPS', 'Hedge call': 'OTM calls', 'Insurance put': 'Insurance puts' };
    const L = b.sold.map(([K, sd0, q, at, now], i) => ({ k: 's' + i, g: 's', ty: sd0 === 'c' ? 'C' : 'P', K, q: -q, T: 3, ex: 'Oct 30', t: (sd0 === 'c' ? 'Calls ' : 'Puts ') + fk(K) + ' ×' + q + ', Oct 30' }))
      .concat(b.sh ? [{ k: 'sh', g: 'l', ty: 'S', K: b.sh[1], q: b.sh[0], T: 0, ex: '', t: 'Shares ' + n0(b.sh[0]) + ' at $' + b.sh[1].toFixed(2) }] : [])
      .concat(b.legs.map(([nm, K, q, ex], i) => ({ k: 'l' + i, g: 'l', ty: nm === 'Insurance put' ? 'P' : 'C', K, q, T: XD[ex] || 300, ex, t: (NM[nm] || nm) + ' ' + fk(K) + ' ×' + q + ', ' + ex })));
    const E = b.sold.reduce((a, [K, sd0, q, at, now]) => a + q * 100 * (at - now), 0);
    const val = (l, S, tt) => l.ty === 'S' ? l.q * S : l.q * 100 * bs(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P');
    const lpl = (l, S, tt) => val(l, S, tt) - val(l, S0, 0), ldl = (l, S, tt) => l.ty === 'S' ? l.q : l.q * 100 * dl(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P');
    // Nov 6 (Nik): any leg can be switched off with a tap · OFF = keys left out of every total, the chart, the Greeks and the fixes
    const OFF = new Set(), on = l => !OFF.has(l.k), E1 = () => OFF.size ? b.sold.reduce((a, [K, sd0, q, at, now], i) => OFF.has('s' + i) ? a : a + q * 100 * (at - now), 0) : E;
    const PL = (S, tt, X) => L.filter(on).concat(X || []).reduce((a, l) => a + lpl(l, S, tt), 0) + E1(), Dl = (S, tt, X) => L.filter(on).concat(X || []).reduce((a, l) => a + ldl(l, S, tt), 0);
    const ST = [[0, 'Today', 'today', 'Tue Oct 27'], [1, 'Wed', 'on Wednesday', 'Wed Oct 28'], [2, 'Thu', 'on Thursday', 'Thu Oct 29'], [2.9, 'Oct 30', 'at the Oct 30 close', 'Fri Oct 30 close'], [6, 'Mon', 'on Mon Nov 2', 'Mon Nov 2'], [7, 'Tue', 'on Tue Nov 3', 'Tue Nov 3'], [8, 'Wed', 'on Wed Nov 4', 'Wed Nov 4'], [9, 'Thu', 'on Thu Nov 5', 'Thu Nov 5'], [9.9, 'Nov 6', 'at the Nov 6 close', 'Fri Nov 6 close']];
    const GR = []; for (let i = 0; i <= 140; i++) GR.push(X0 + (X1 - X0) * i / 140);
    const Xs = S => (S - X0) / (X1 - X0) * W; let mn = 0, mx = 0; ST.forEach(([tt]) => GR.forEach(S => { const p = PL(S, tt); if (p < mn) mn = p; if (p > mx) mx = p; }));
    const pMx = mx * 1.12 || 1, pMn = mn * 1.1 || -1, Y = p => (pMx - p) / (pMx - pMn) * H, pth = f => GR.map((S, i) => (i ? 'L' : 'M') + Xs(S).toFixed(1) + ' ' + Math.max(-30, Math.min(H + 20, Y(f(S)))).toFixed(1)).join(' ');
    const FL = {}, flip = tt => { const fk0 = tt + '|' + [...OFF].sort().join(','); if (fk0 in FL) return FL[fk0]; tt = +tt; let pos = false, r = null; for (let i = 0; i <= 400; i++) { const S = X0 + (X1 * 1.05 - X0) * i / 400, d = Dl(S, tt); if (d > 0) pos = true; else if (pos) { r = S; break; } } return FL[fk0] = r; };
    const gk = (S, tt) => ({ d: Dl(S, tt), g: (Dl(S + S * .002, tt) - Dl(S - S * .002, tt)) / (S * .004), th: (PL(S, tt + .05) - PL(S, tt)) / .05, vg: L.filter(on).reduce((a, l) => l.ty === 'S' ? a : a + l.q * 100 * (bsV(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P', v + .01) - bsV(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P', v)), 0) });
    const st0 = [.5, 1, 2, 2.5, 5, 10, 20, 25, 50].find(x => (X1 - X0) / x <= 5) || 50, ax = []; for (let k = Math.ceil(X0 / st0) * st0; k <= X1; k += st0) ax.push(k);
    const cl = D.series(t).v || [], sma = cl.length >= 20 ? cl.slice(-20).reduce((a, x) => a + x, 0) / 20 : null, hi = cl.length ? Math.max(...cl) : null, lo = cl.length ? Math.min(...cl) : null;
    const wl = (D.walls(t).w || []).filter(w => w[0] >= X0 && w[0] <= X1 && w[2] !== 'Unclear').sort((a, c) => a[3] - c[3]).slice(0, 3);
    return C[t] = { OFF, t, S0, P0, v, W, H, X0, X1, L, E, bs, dl, lpl, ldl, PL, D: Dl, Xs, Y, pth, y0: Y(0), ST, flip, gk, G0: gk(S0, 0), ax, sma, hi, lo, wl, sd: S0 * v * Math.sqrt(5 / 252) };
  }
```

### Legs and premium already earned

`L`: sold legs (T = 3, ex Oct 30), shares, long legs; `E` = Σ qty × 100 × (sold at − now), the premium already earned, added to every P&L.

**Inputs:** BOOK  
**Source:** `reference/SunnyPositions.dc.html` lines 408-411 (verbatim)

```js
    const L = b.sold.map(([K, sd0, q, at, now], i) => ({ k: 's' + i, g: 's', ty: sd0 === 'c' ? 'C' : 'P', K, q: -q, T: 3, ex: 'Oct 30', t: (sd0 === 'c' ? 'Calls ' : 'Puts ') + fk(K) + ' ×' + q + ', Oct 30' }))
      .concat(b.sh ? [{ k: 'sh', g: 'l', ty: 'S', K: b.sh[1], q: b.sh[0], T: 0, ex: '', t: 'Shares ' + n0(b.sh[0]) + ' at $' + b.sh[1].toFixed(2) }] : [])
      .concat(b.legs.map(([nm, K, q, ex], i) => ({ k: 'l' + i, g: 'l', ty: nm === 'Insurance put' ? 'P' : 'C', K, q, T: XD[ex] || 300, ex, t: (NM[nm] || nm) + ' ' + fk(K) + ' ×' + q + ', ' + ex })));
    const E = b.sold.reduce((a, [K, sd0, q, at, now]) => a + q * 100 * (at - now), 0);
```

### P&L and delta by leg and in total, legs switched off

`lpl` = value at (S, tt) minus value now; `ldl` = delta in shares; `OFF` = legs tapped off; `PL(S, tt, X)` and `D(S, tt, X)` sum the legs that are on plus any extra fix legs X.

**Inputs:** L, OFF  
**Source:** `reference/SunnyPositions.dc.html` lines 412-416 (verbatim)

```js
    const val = (l, S, tt) => l.ty === 'S' ? l.q * S : l.q * 100 * bs(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P');
    const lpl = (l, S, tt) => val(l, S, tt) - val(l, S0, 0), ldl = (l, S, tt) => l.ty === 'S' ? l.q : l.q * 100 * dl(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P');
    // Nov 6 (Nik): any leg can be switched off with a tap · OFF = keys left out of every total, the chart, the Greeks and the fixes
    const OFF = new Set(), on = l => !OFF.has(l.k), E1 = () => OFF.size ? b.sold.reduce((a, [K, sd0, q, at, now], i) => OFF.has('s' + i) ? a : a + q * 100 * (at - now), 0) : E;
    const PL = (S, tt, X) => L.filter(on).concat(X || []).reduce((a, l) => a + lpl(l, S, tt), 0) + E1(), Dl = (S, tt, X) => L.filter(on).concat(X || []).reduce((a, l) => a + ldl(l, S, tt), 0);
```

### Date slider stops (ST)

One stop per trading day to the last sold expiry: `[days, short label, phrase, long label]`; the Oct 30 close is 2.9 days.

**Inputs:** -  
**Source:** `reference/SunnyPositions.dc.html` lines 417 (verbatim)

```js
    const ST = [[0, 'Today', 'today', 'Tue Oct 27'], [1, 'Wed', 'on Wednesday', 'Wed Oct 28'], [2, 'Thu', 'on Thursday', 'Thu Oct 29'], [2.9, 'Oct 30', 'at the Oct 30 close', 'Fri Oct 30 close'], [6, 'Mon', 'on Mon Nov 2', 'Mon Nov 2'], [7, 'Tue', 'on Tue Nov 3', 'Tue Nov 3'], [8, 'Wed', 'on Wed Nov 4', 'Wed Nov 4'], [9, 'Thu', 'on Thu Nov 5', 'Thu Nov 5'], [9.9, 'Nov 6', 'at the Nov 6 close', 'Fri Nov 6 close']];
```

### Price grid, chart scale, turns short (flip), Greeks

141 price points across the chart; `flip(tt)` = first price above today where delta drops below zero (400 steps); `gk` = delta, gamma (finite difference ±.2%), theta (P&L change over .05 day, per day), vega.

**Inputs:** PL, D  
**Source:** `reference/SunnyPositions.dc.html` lines 418-423 (verbatim)

```js
    const GR = []; for (let i = 0; i <= 140; i++) GR.push(X0 + (X1 - X0) * i / 140);
    const Xs = S => (S - X0) / (X1 - X0) * W; let mn = 0, mx = 0; ST.forEach(([tt]) => GR.forEach(S => { const p = PL(S, tt); if (p < mn) mn = p; if (p > mx) mx = p; }));
    const pMx = mx * 1.12 || 1, pMn = mn * 1.1 || -1, Y = p => (pMx - p) / (pMx - pMn) * H, pth = f => GR.map((S, i) => (i ? 'L' : 'M') + Xs(S).toFixed(1) + ' ' + Math.max(-30, Math.min(H + 20, Y(f(S)))).toFixed(1)).join(' ');
    const FL = {}, flip = tt => { const fk0 = tt + '|' + [...OFF].sort().join(','); if (fk0 in FL) return FL[fk0]; tt = +tt; let pos = false, r = null; for (let i = 0; i <= 400; i++) { const S = X0 + (X1 * 1.05 - X0) * i / 400, d = Dl(S, tt); if (d > 0) pos = true; else if (pos) { r = S; break; } } return FL[fk0] = r; };
    const gk = (S, tt) => ({ d: Dl(S, tt), g: (Dl(S + S * .002, tt) - Dl(S - S * .002, tt)) / (S * .004), th: (PL(S, tt + .05) - PL(S, tt)) / .05, vg: L.filter(on).reduce((a, l) => l.ty === 'S' ? a : a + l.q * 100 * (bsV(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P', v + .01) - bsV(S, l.K, Math.max(0, l.T - tt) / 365, l.ty === 'P', v)), 0) });
    const st0 = [.5, 1, 2, 2.5, 5, 10, 20, 25, 50].find(x => (X1 - X0) / x <= 5) || 50, ax = []; for (let k = Math.ceil(X0 / st0) * st0; k <= X1; k += st0) ax.push(k);
```

### Model outputs and priced move

`sd` = S0 × IV × √(5/252) (dollars), used by the logo-strip dot.

**Inputs:** -  
**Source:** `reference/SunnyPositions.dc.html` lines 424-426 (verbatim)

```js
    const cl = D.series(t).v || [], sma = cl.length >= 20 ? cl.slice(-20).reduce((a, x) => a + x, 0) / 20 : null, hi = cl.length ? Math.max(...cl) : null, lo = cl.length ? Math.min(...cl) : null;
    const wl = (D.walls(t).w || []).filter(w => w[0] >= X0 && w[0] <= X1 && w[2] !== 'Unclear').sort((a, c) => a[3] - c[3]).slice(0, 3);
    return C[t] = { OFF, t, S0, P0, v, W, H, X0, X1, L, E, bs, dl, lpl, ldl, PL, D: Dl, Xs, Y, pth, y0: Y(0), ST, flip, gk, G0: gk(S0, 0), ax, sma, hi, lo, wl, sd: S0 * v * Math.sqrt(5 / 252) };
```

### Book totals (the sideways row) and the whole-name book

Long: Shares (value, today), LEAPS (T > 400), OTM calls, Insurance puts; Sold · left to earn: Calls, Puts. Values at today's price.

**Inputs:** M.L, Q  
**Source:** `reference/SunnyPositions.dc.html` lines 436-441 (verbatim)

```js
    // the ticker's whole book (Nov 6, from Search Explorations 47a): what you hold in this name today, empty lines left out
    const tot = { sh: [0, 0], lp: [0, 0], oc: [0, 0], ip: [0, 0], sc: [0, 0], sp: [0, 0] }, mvT = M.S0 - M.P0;
    M.L.forEach(l => { if (l.ty === 'S') { tot.sh[0] += l.q * M.S0; tot.sh[1] += l.q * mvT; return; } if (l.q < 0) { const bk = D.BOOK[t].sold.find(y => y[0] === l.K && (y[1] === 'c') === (l.ty === 'C')), key = l.ty === 'C' ? 'sc' : 'sp'; if (bk) { tot[key][0] += bk[2] * 100 * bk[4]; tot[key][1] += bk[2] * 100 * (bk[3] - bk[4]); } return; }
      const key = l.ty === 'P' ? 'ip' : l.T > 400 ? 'lp' : 'oc'; tot[key][0] += l.q * 100 * M.bs(M.S0, l.K, l.T / 365, l.ty === 'P'); tot[key][1] += M.ldl(l, M.S0, 0) * mvT; });
    const it = (k, l, a, sub) => ({ k, l, raw: a, v: fK(a[0]), s: sub ? sub(a[1]) : (a[1] < 0 ? '▼ ' : '▲ ') + fK(a[1]) + ' today', sc: sub ? GN : a[1] < 0 ? RD : GN });
    const sum = [{ k: 'l', h: 'Long', items: [it('sh', 'Shares', tot.sh), it('lp', 'LEAPS', tot.lp), it('oc', 'OTM calls', tot.oc), it('ip', 'Insurance puts', tot.ip)] }, { k: 's', h: 'Sold · left to earn', items: [it('sc', 'Calls', tot.sc, x => fK(x) + ' kept'), it('sp', 'Puts', tot.sp, x => fK(x) + ' kept')] }].map(g => Object.assign(g, { items: g.items.filter(x => x.raw[0] || x.raw[1]) })).filter(g => g.items.length);
```

### Logo strip dot (short at the priced move by Friday)

`warn = D(S0 + sd, 2.9) < 0`, the same test as Home.

**Inputs:** m45  
**Source:** `reference/SunnyPositions.dc.html` lines 442 (verbatim)

```js
    const strip = BK.map(x => { const m = this.m45(x), on = x === t, warn = m ? m.D(m.S0 + m.sd, 2.9) < 0 : false; return { k: x, t: x, logo: 'assets/logos/' + x + '.png', on: String(on), fw: on ? 700 : 600, c: on ? INK : MU, ring: on ? '0 0 0 2px ' + INK + ',0 0 0 .5px rgba(0,0,0,.12)' : '0 0 0 .5px rgba(0,0,0,.12)', dot: warn ? 1 : 0, a: (CO[x] || x) + (warn ? ', short if it rises its priced move by Friday' : ''), go: h('n' + x, () => { this._pn = x; set({ pn45: x }); }) }; });
```

### Selected date and price; P&L, delta, turns short at that stop

Opening from Home jumps to the first stop ≥ 2.9 (Friday close). `need` = shares of delta missing to get back to zero.

**Inputs:** ST, state  
**Source:** `reference/SunnyPositions.dc.html` lines 444-447 (verbatim)

```js
    const offK = stt[pre + 'o'] || {}; M.OFF.clear(); Object.keys(offK).forEach(k => { if (offK[k]) M.OFF.add(k); });
    const fri = this._pfd === t ? Math.max(0, M.ST.findIndex(x => x[0] >= 2.9)) : null; if (fri != null) { this._pfd = null; setTimeout(() => this.setState({ [pre + 'd']: fri, [pre + 's']: undefined }), 0); }
    const ST = M.ST, n = ST.length - 1, di = fri ?? stt[pre + 'd'] ?? 0, [tt, , tl, tr] = ST[di], S = stt[pre + 's'] ?? M.S0, ly = stt[pre + 'l'] || { w: false, tc: false }, lf = stt[pre + 'f'] || 'a', xo = !!stt[pre + 'x'];
    const pl = M.PL(S, tt), d = M.D(S, tt), fl = M.flip(tt), need = Math.max(0, -d), past = tt > 3;
```

### Leg rows (ending text, off switch)

Each leg's P&L and delta at the chosen price and date; "Ends at this close" / "Ended Oct 30" lines.

**Inputs:** M.L  
**Source:** `reference/SunnyPositions.dc.html` lines 448-452 (verbatim)

```js
    const exT = (l, ex) => { const itm = l.ty === 'C' ? S > l.K : S < l.K, sold = l.q < 0, by = '$' + Math.abs(S - l.K).toFixed(2);
      if (ex === 'past') return 'Ended ' + l.ex + (itm ? ', ' + by + ' in the money if ' + t + ' is at ' + fp(S) + (sold ? '. You’d roll them before that close, so no shares go.' : '.') : ', worth nothing at ' + fp(S) + (sold ? ': kept in full.' : '.'));
      return 'Ends at this close' + (itm ? ', ' + by + ' in the money' + (sold ? ': roll or buy back before 4 PM.' : ': sell before 4 PM.') : ', worth nothing at ' + fp(S) + (sold ? ': you keep it all.' : '.')); };
    const rows = M.L.map(l => { const off = M.OFF.has(l.k), p = off ? 0 : M.lpl(l, S, tt), dd = M.ldl(l, S, tt), left = l.T - tt, ex = l.ty !== 'S' && left <= .15 ? (left < -.05 ? 'past' : 'at') : '', ps = ex === 'past', hurt = p < -.5 && !ps && !off;
      return { k: l.k, off, op: off ? .45 : 1, tg: off ? 'Off · tap to add back' : '', tgO: off ? 1 : 0, sw: String(!off), tap: h(pre + 'o' + l.k, () => this.setState(s0 => { const c0 = Object.assign({}, s0[pre + 'o'] || {}); c0[l.k] = !c0[l.k]; return { [pre + 'o']: c0, [pre + 'w']: null }; })), g: ps ? 'x' : l.g, xg: l.g, l, p, t: l.t, v: off ? 'Off' : Math.abs(p) < .5 ? '$0' : f$(p), vc: off || Math.abs(p) < .5 || ps ? MU : hurt ? RD : GN, bg: hurt ? (dk ? 'rgba(255,105,97,.14)' : 'rgba(188,46,48,.08)') : ROWBG, dv: ex ? '' : 'Δ ' + fn(dd), dc: dd < 0 ? RD : INK, at: ex ? exT(l, ex) : l.ty === 'S' ? ' · cost $' + l.K.toFixed(2) + ', no decay' : ' at ' + fp(S), rel: !ps && !off, a: l.t + (off ? ', switched off. Tap to add it back' : ', ' + ud(p) + ' from today' + (hurt ? ', hurting' : '') + '. Tap to switch it off'), hasSg: false, sg: '' }; });
```

### Fixes: Release, OTM calls, Shares

Only when short (`need > 0`). Release = buy back the sold call that hurts most, enough contracts to cover `need` at its delta, capped at what was sold. OTM calls = Sep ’27 calls at ~7.5% out (strike rounded to .5 under $50, 1 under $200, else 5), enough to cover `need`, cost at today's price. Shares = `need` rounded up to whole hundreds. Each shows cost, then delta and P&L after (`M.D(S, tt, f.X)`, `M.PL(S, tt, f.X)`).

**Inputs:** rows, need, M  
**Source:** `reference/SunnyPositions.dc.html` lines 453-461 (verbatim)

```js
    const now = (K, T, put) => M.bs(M.S0, K, T / 365, put), fixes = [], worst = rows.filter(r => r.l.q < 0 && r.l.ty === 'C' && r.rel && r.p < 0).sort((a, c) => a.p - c.p)[0];
    const oK = Math.round(M.S0 * 1.075 / (M.S0 < 50 ? .5 : M.S0 < 200 ? 1 : 5)) * (M.S0 < 50 ? .5 : M.S0 < 200 ? 1 : 5);
    if (need > 0) {
      if (worst) { const l = worst.l, pc = Math.max(.01, M.dl(S, l.K, Math.max(0, l.T - tt) / 365)), k0 = Math.min(-l.q, Math.ceil(need / (100 * pc))); fixes.push({ k: 'rel', t: 'Release', cost: f$(k0 * 100 * now(l.K, l.T)), act: 'Buy back ' + k0 + ' of the ' + (-l.q) + ' ' + l.K + ' calls, ' + l.ex, X: [{ k: 'x', ty: 'C', K: l.K, q: k0, T: l.T }], n: k0, of: -l.q }); }
      const on = Math.ceil(need / (100 * Math.max(.05, M.dl(S, oK, (325 - tt) / 365)))); fixes.push({ k: 'otm', t: 'OTM calls', cost: f$(on * 100 * now(oK, 325)), act: 'Buy ' + on + ' Sep ’27 ' + oK + ' calls, about 7.5% out. Their delta grows as ' + t + ' rises, like the sold calls’', X: [{ k: 'x', ty: 'C', K: oK, q: on, T: 325 }] });
      const sn = Math.ceil(need / 100) * 100; fixes.push({ k: 'sh', t: 'Shares', cost: f$(sn * M.S0), act: 'Buy ' + sn.toLocaleString('en-US') + ' shares at ' + fp(M.S0) + '. No decay, ' + (sn / 100) + ' more calls to sell', X: [{ k: 'x', ty: 'S', K: M.S0, q: sn, T: 0 }] }); }
    const ws = stt[pre + 'w'], wsel = fixes.find(f => f.k === ws) || null;
    fixes.forEach(f => { const ad = M.D(S, tt, f.X), ap = M.PL(S, tt, f.X), on = f === wsel; Object.assign(f, { res: 'Then ' + ls(ad) + ' · ' + ud(ap), rc: ad < 0 ? RD : GN, on: String(on), bg: on ? THBG : MK, sh: on ? 'inset 0 0 0 2px ' + INK + ',0 4px 12px rgba(0,0,0,.08)' : 'none', go: h(pre + 'w' + f.k, () => this.setState(s0 => ({ [pre + 'w']: s0[pre + 'w'] === f.k ? null : f.k }))) }); });
    const rl = fixes.find(f => f.k === 'rel'); if (worst && rl) { const rr = rows.find(r => r.k === worst.k); rr.hasSg = true; rr.sg = rl.n >= rl.of && M.D(S, tt, rl.X) < 0 ? 'Hurting most. Buying back all ' + rl.of + ' still leaves you short: see the fixes below' : 'Buy back ' + rl.n + ' to turn it green · ' + rl.cost; }
```

### Sections and legs list

Sold / Long groups, legs off count, "Nothing sold this week".

**Inputs:** rows  
**Source:** `reference/SunnyPositions.dc.html` lines 462-465 (verbatim)

```js
    const nOff = rows.filter(r => r.off).length, pick = k => rows.filter(r => r.g === k), add = a => a.reduce((x, r) => x + r.p, 0), mkS = (k, h0, rs, ended) => { const v0 = add(rs); return { k, h: h0, v: (ended ? 'Settled, ' : '') + (v0 < 0 ? (ended ? 'down ' : 'Down ') : (ended ? 'up ' : 'Up ')) + f$(v0) + ' from today', c: Math.abs(v0) < .5 ? MU : v0 < 0 ? RD : GN, rows: ended && !xo ? [] : rs, open: String(ended ? xo : true), tog: ended ? h(pre + 'xt', () => this.setState(s0 => ({ [pre + 'x']: !s0[pre + 'x'] }))) : null, cur: ended ? 'pointer' : 'default', chO: ended ? 1 : 0, rot: xo ? '180deg' : '0deg' }; };
    const xp = rows.filter(r => r.g === 'x' && (lf === 'a' || r.xg === lf)), sold = pick('s');
    const secs = (lf === 'a' ? [mkS('s', 'Sold', sold), mkS('l', 'Long', pick('l'))] : lf === 's' ? [mkS('s', 'Sold', sold)] : [mkS('l', 'Long', pick('l'))]).filter(g => g.rows.length).concat(xp.length ? [mkS('x', 'Ended ' + xp[0].l.ex, xp, true)] : []);
    if (!sold.length && !xp.length && lf !== 'l') secs.unshift({ k: 'none', h: 'Sold', v: 'Nothing sold this week', c: MU, rows: [], open: 'true', tog: null, cur: 'default', chO: 0, rot: '0deg' });
```

### Chart line, drag, status, story, Greeks row

Status: Long and making · Making, but short · Losing · Losing, and short. Story: "At $S {date} you are up/down $x and long/short n Δ. You turn short above $flip".

**Inputs:** M, S, tt  
**Source:** `reference/SunnyPositions.dc.html` lines 466-476 (verbatim)

```js
    // chart
    const line = M.pth(x => M.PL(x, tt)), KX = {}, ticks = M.L.filter(l => l.ty !== 'S' && l.K >= M.X0 && l.K <= M.X1).map(l => { const i = KX[l.K] = (KX[l.K] ?? -1) + 1, r = rows.find(x => x.k === l.k); return { k: l.k, x: (M.Xs(l.K) + ([0, -6, 6, -12][i] || 0)).toFixed(1), y1: (M.H + 5 + Math.min(10, 3 + Math.abs(l.q) / 60 * 7)).toFixed(1), c: r.p < -.5 && r.rel ? RD : l.ty === 'C' ? NV : BRN, o: r.off ? .12 : !r.rel ? .2 : l.q < 0 ? 1 : .4 }; });
    const scr = h(pre + 'sc', e => { const r = e.currentTarget.getBoundingClientRect(), x = M.X0 + Math.max(0, Math.min(1, (e.clientX - r.left) / Math.max(1, r.width))) * (M.X1 - M.X0), stp = M.S0 < 50 ? .05 : M.S0 < 200 ? .1 : .5, q = Math.round(x / stp) * stp; if (Math.abs(q - (this.state[pre + 's'] ?? -1)) > 1e-9) set({ [pre + 's']: +q.toFixed(2) }); });
    const zl = pl < 0 ? (d < 0 ? 'Losing, and short' : 'Losing') : d < 0 ? 'Making, but short' : 'Long and making', zc = pl < 0 ? RD : d < 0 ? OR : GN;
    const sp = (t0, fw, c) => ({ t: t0, fw: fw || 500, c: c || INK }), wr = worst ? rows.find(r => r.k === worst.k) : null, SY = [sp('At ' + fp(S) + ' ' + tl + ' you are '), sp(ud(pl), 700, pl < 0 ? RD : GN)];
    if (need > 0) SY.push(sp(' but '), sp('short ' + fd(d), 700, RD), sp('.' + (wr ? ' The ' + wr.l.K + ' calls hurt most.' : '')));
    else SY.push(sp(' and long ' + fd(d) + '.'), sp(fl != null && fl <= M.X1 ? ' You turn short above ' : ' You stay long across the chart.'), sp(fl != null && fl <= M.X1 ? fp(fl) + '.' : '', 700, OR));
    if (past && M.L.some(l => l.q < 0 && l.T <= 3)) SY.push(sp(' This week’s calls have ended; next week’s aren’t sold yet.'));
    if (nOff) SY.push(sp(' ' + nOff + (nOff > 1 ? ' legs' : ' leg') + ' switched off.', 600, MU));
    SY.forEach((x, i) => { x.k = 's' + i; });
    const gq = M.gk(S, tt), gk = [['d', 'Delta', fn], ['th', 'Theta', f$], ['g', 'Gamma', fn], ['vg', 'Vega', f$]].map(([k, l, fm]) => { const x = gq[k]; return { k, l, v: fm(x), c: x < 0 ? RD : k === 'th' ? GN : INK }; });
```

### Priced move band on the chart

Shaded band = S0 × IV × √(max(tt, 1)/365): calendar days over 365 here, unlike Home (see Differences).

**Inputs:** M, tt  
**Source:** `reference/SunnyPositions.dc.html` lines 488 (verbatim)

```js
    const sdx = M.S0 * M.v * Math.sqrt(Math.max(tt, 1) / 365), dpick = h(pre + 'dp', e => { const r = e.currentTarget.getBoundingClientRect(), f = (e.clientX - r.left - 14) / Math.max(1, r.width - 28), i = Math.max(0, Math.min(n, Math.round(f * n))); if (i !== (this.state[pre + 'd'] ?? 0)) set({ [pre + 'd']: i }); });
```

## Overview checks (`New Home iPhone Preview.dc.html`, the `bo` block)

There is **no code behind the six checks**: the template hard-codes the figures (sample at Tue Oct 27) and only the account names come from props. The rules to implement are in README §8; the engine pieces they reuse are noted.


### Overview template (the literal sample)

Header, sentence, tally, six checks, Coming in.

**Inputs:** props nameA, nameB  
**Source:** `reference/New Home iPhone Preview.dc.html` lines 195-206 (verbatim)

```js
          <sc-if value="{{ bo.has }}" hint-placeholder-val="{{ false }}"><div ref="{{ bo.sRef }}" style="position:absolute;inset:0;overflow-y:auto;scrollbar-width:none;overscroll-behavior:contain;padding:76px 20px 128px;box-sizing:border-box;display:flex;flex-direction:column;color:var(--ink)">
            <div style="flex:none;display:flex;flex-direction:column;gap:14px;padding-bottom:24px"><span style="font-size:15px;line-height:20px;font-weight:600;color:var(--muted)">Both accounts · Tue Oct 27</span><p style="margin:0;font-size:28px;line-height:34px;font-weight:600;letter-spacing:-.02em;color:var(--muted);text-wrap:pretty">Both books are <span style="color:var(--ink)">on pace</span> this week. A bad week would cost <span style="color:var(--ink)">5.6%</span>, and the puts cover only <span style="color:var(--ink)">a quarter</span> of the shares.</p><div style="display:flex;flex-wrap:wrap;align-items:center;gap:6px 16px;font-size:14px;line-height:18px;font-weight:600"><span style="display:flex;align-items:center;gap:6px;color:var(--gr)"><span aria-hidden="true" style="flex:none;width:8px;height:8px;border-radius:50%;background:currentColor"></span>3 on track</span><span style="display:flex;align-items:center;gap:6px;color:{{ bo.or }}"><span aria-hidden="true" style="flex:none;width:8px;height:8px;border-radius:50%;background:currentColor"></span>3 to watch</span><span style="color:var(--muted)">5 trades to place</span></div></div>
            <div role="list" aria-label="Six checks" style="flex:none;display:flex;flex-direction:column;border-top:1px solid var(--line)">
              <div role="group" aria-label="Downside, Watch" style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 12px;align-items:center;padding:18px 0;border-top:none"><span style="font-size:15px;line-height:20px;font-weight:600">Downside</span><span style="display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:600;color:{{ bo.or }}"><span aria-hidden="true" style="flex:none;width:7px;height:7px;border-radius:50%;background:currentColor"></span>Watch</span><span style="grid-column:1 / -1;font-size:40px;line-height:46px;font-weight:800;letter-spacing:-.03em;color:var(--rd);font-variant-numeric:tabular-nums">$77,068</span><span style="grid-column:1 / -1;font-size:15px;line-height:21px;font-weight:500;text-wrap:pretty">Lost by Friday if every name falls its priced move, 5.6% of what both books hold.</span><span style="grid-column:1 / -1;display:flex;flex-wrap:wrap;gap:4px 16px;padding-top:4px;font-size:13px;line-height:18px;font-weight:600;color:var(--muted)"><span>Puts cover 26% of the shares</span><span>{{ bo.nA }} 27%</span><span>{{ bo.nB }} 23%</span></span></div>
              <div role="group" aria-label="Concentration, Watch" style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 12px;align-items:center;padding:18px 0;border-top:1px solid var(--line)"><span style="font-size:15px;line-height:20px;font-weight:600">Concentration</span><span style="display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:600;color:{{ bo.or }}"><span aria-hidden="true" style="flex:none;width:7px;height:7px;border-radius:50%;background:currentColor"></span>Watch</span><span style="grid-column:1 / -1;font-size:40px;line-height:46px;font-weight:800;letter-spacing:-.03em;color:var(--ink);font-variant-numeric:tabular-nums">40%</span><span style="grid-column:1 / -1;font-size:15px;line-height:21px;font-weight:500;text-wrap:pretty">Of both books sits in Nike and Netflix. Both hold the same seven names, so they rise and fall together.</span><span style="grid-column:1 / -1;display:flex;flex-wrap:wrap;gap:4px 16px;padding-top:4px;font-size:13px;line-height:18px;font-weight:600;color:var(--muted)"><span>Nike 21%</span><span>Netflix 19%</span><span>Alibaba 17%</span></span></div>
              <div role="group" aria-label="Pace, On track" style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 12px;align-items:center;padding:18px 0;border-top:1px solid var(--line)"><span style="font-size:15px;line-height:20px;font-weight:600">Pace</span><span style="display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:600;color:var(--gr)"><span aria-hidden="true" style="flex:none;width:7px;height:7px;border-radius:50%;background:currentColor"></span>On track</span><span style="grid-column:1 / -1;font-size:40px;line-height:46px;font-weight:800;letter-spacing:-.03em;color:var(--ink);font-variant-numeric:tabular-nums">0.60%</span><span style="grid-column:1 / -1;font-size:15px;line-height:21px;font-weight:500;text-wrap:pretty">Kept this week on what both bought, if Friday goes to plan. A usual week is 0.50%.</span><span style="grid-column:1 / -1;display:flex;flex-wrap:wrap;gap:4px 16px;padding-top:4px;font-size:13px;line-height:18px;font-weight:600;color:var(--muted)"><span>{{ bo.nA }} 0.61%</span><span>{{ bo.nB }} 0.58%</span></span></div>
              <div role="group" aria-label="Calls at work, On track" style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 12px;align-items:center;padding:18px 0;border-top:1px solid var(--line)"><span style="font-size:15px;line-height:20px;font-weight:600">Calls at work</span><span style="display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:600;color:var(--gr)"><span aria-hidden="true" style="flex:none;width:7px;height:7px;border-radius:50%;background:currentColor"></span>On track</span><span style="grid-column:1 / -1;font-size:40px;line-height:46px;font-weight:800;letter-spacing:-.03em;color:var(--ink);font-variant-numeric:tabular-nums">93%</span><span style="grid-column:1 / -1;font-size:15px;line-height:21px;font-weight:500;text-wrap:pretty">Of the 20,300 shares have a call sold this week, one per 100. Lululemon is the gap in both.</span><span style="grid-column:1 / -1;display:flex;flex-wrap:wrap;gap:4px 16px;padding-top:4px;font-size:13px;line-height:18px;font-weight:600;color:var(--muted)"><span>{{ bo.nA }} 93%</span><span>{{ bo.nB }} 92%</span></span></div>
              <div role="group" aria-label="Delta, Watch" style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 12px;align-items:center;padding:18px 0;border-top:1px solid var(--line)"><span style="font-size:15px;line-height:20px;font-weight:600">Delta</span><span style="display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:600;color:{{ bo.or }}"><span aria-hidden="true" style="flex:none;width:7px;height:7px;border-radius:50%;background:currentColor"></span>Watch</span><span style="grid-column:1 / -1;font-size:40px;line-height:46px;font-weight:800;letter-spacing:-.03em;color:var(--ink);font-variant-numeric:tabular-nums">3 of 14</span><span style="grid-column:1 / -1;font-size:15px;line-height:21px;font-weight:500;text-wrap:pretty">Names turn short if they rise their priced move by Friday: Nike in both books, Alibaba in {{ bo.nB }}’s. All 14 are long today.</span><span style="grid-column:1 / -1;display:flex;flex-wrap:wrap;gap:4px 16px;padding-top:4px;font-size:13px;line-height:18px;font-weight:600;color:var(--muted)"><span>{{ bo.nA }} 1 short · 2 thin</span><span>{{ bo.nB }} 2 short</span></span></div>
              <div role="group" aria-label="To do, On track" style="display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 12px;align-items:center;padding:18px 0;border-top:1px solid var(--line)"><span style="font-size:15px;line-height:20px;font-weight:600">To do</span><span style="display:flex;align-items:center;gap:6px;font-size:13px;line-height:18px;font-weight:600;color:var(--gr)"><span aria-hidden="true" style="flex:none;width:7px;height:7px;border-radius:50%;background:currentColor"></span>On track</span><span style="grid-column:1 / -1;font-size:40px;line-height:46px;font-weight:800;letter-spacing:-.03em;color:var(--ink);font-variant-numeric:tabular-nums">5</span><span style="grid-column:1 / -1;font-size:15px;line-height:21px;font-weight:500;text-wrap:pretty">Trades to place, none late. Alibaba and Lululemon in {{ bo.nA }}’s, Lululemon in {{ bo.nB }}’s.</span><span style="grid-column:1 / -1;display:flex;flex-wrap:wrap;gap:4px 16px;padding-top:4px;font-size:13px;line-height:18px;font-weight:600;color:var(--muted)"><span>{{ bo.nA }} 4</span><span>{{ bo.nB }} 1</span></span></div>
            </div>
            <div style="flex:none;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:2px 12px;align-items:baseline;padding:16px 0 0;border-top:1px solid var(--line)"><span style="font-size:15px;line-height:20px;font-weight:600">Coming in</span><span style="font-size:17px;line-height:22px;font-weight:800;color:var(--gr);font-variant-numeric:tabular-nums">$6,245</span><span style="grid-column:1 / -1;font-size:13px;line-height:18px;font-weight:500;color:var(--muted);text-wrap:pretty">Dividends by Dec 8 from Nike, PepsiCo and FIS · {{ bo.nA }} $4,598 · {{ bo.nB }} $1,647 · kept apart from pace</span></div>
          </div></sc-if>
```

| Check | Rule (README §8) | Reuses |
|---|---|---|
| Downside | P&L by Friday if every name falls its priced move (−sd per name), both books; % of what both hold. Chips: put cover both, per account (`cov` above) | `at(-sd, th)` per name from rv46; put cover from rv46 |
| Concentration | share of both books in the two biggest names; Watch if one name > 35% or top three > 70% | market value per name (Book totals) |
| Pace | kept this week ÷ base (both books), vs a usual week (4-week average) | `soldSum`, `baseOf` |
| Calls at work | sold calls ÷ (shares ÷ 100), capped at 100% a name, over all shares | `BOOK.sold`, `BOOK.sh` |
| Delta | names short at their priced move by Friday, both books (rv46 rows with `st === 2`); chips "1 short · 2 thin" per account | rv46 rows |
| To do | trades to place (the To do rows, `TD`), none late; per account | `TD` |


## Differences to settle (prototype vs README)

1. **"A 1% rise makes you"**: the code uses dollar delta now (`Σ net delta × price / 100` at t0), not P&L(+1%) − P&L(0) by Friday as block 30 says.
2. **Turns-short search grid**: Home steps .05% of the name's price (`fp`), the Positions chart 400 price steps across the chart, so Home says $36.23 and Positions $36.24 for Nike (AUDIT-LOG "One cent"). One engine, first cent where net delta crosses zero.
3. **Priced move to a date**: Home and the dot use IV × √(5/252); the Positions band uses IV × √(calendar days/365).
4. **IV**: one per name (`IV[t]`, default .35 in rv46 and m45, .3 in `sd`), no rate, no dividend (README 13.A2).
5. **Sold legs' expiry**: hard-coded 3 calendar days (Oct 30) in both models.
6. **Book turns short** (sentence variant "If the market rises x% by Friday you turn short") is searched on a .25% grid of the whole-book move.


## Expected values for unit tests (rendered prototype, privacy off)

The Your position card is not in `brief-home.json` (the engine makes it); these are the values it rendered on Nov 6, for the engine's unit tests.


**pre · Sunny** (Before the bell · by Friday’s close)  
Sentence: "Long now: a 1% rise makes you $9.3K. The book stays long even if the market rises 10% by Friday, but Nike turns short above $36.23."  
Three numbers: $40K if up 5% · $3.8K flat to Friday · $52K if down 5%  
Cover: "Insurance puts cover 4,000 of your 15,000 shares, 27%. Shares have no floor below that."  
By name (1 short, 2 thin at a priced move):  
- Nike: Short above $36.23 by Friday · Short 917 Δ at ↑4.9%  
- Alibaba: Thin by Friday, never short · Thin at ↑5.6%  
- Netflix: Thin by Friday, never short · Thin at ↑6.3%  
- FIS: Stays long past ↑12.7% · Long 1,134 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 555 Δ at ↑2.5%  
- Uber: Stays long past ↑16.1% · Long 905 Δ at ↑5.4%  
- Lululemon: Stays long past ↑20.3% · Long 1,965 Δ at ↑6.8%


**pre · Nicolay** (Before the bell · by Friday’s close)  
Sentence: "Long now: a 1% rise makes you $2.8K. The book stays long even if the market rises 10% by Friday, but Nike turns short above $36.23."  
Three numbers: $12K if up 5% · $959 flat to Friday · $15K if down 5%  
Cover: "Insurance puts cover 1,200 of your 5,300 shares, 23%. Shares have no floor below that."  
By name (2 short at a priced move):  
- Nike: Short above $36.23 by Friday · Short 262 Δ at ↑4.9%  
- Alibaba: Short above $104.91 by Friday · Short 34 Δ at ↑5.6%  
- Netflix: Stays long past ↑19.0% · Long 383 Δ at ↑6.3%  
- FIS: Stays long past ↑12.7% · Long 454 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 208 Δ at ↑2.5%  
- Uber: Stays long past ↑16.1% · Long 377 Δ at ↑5.4%  
- Lululemon: Stays long past ↑20.3% · Long 517 Δ at ↑6.8%


**open · Sunny** (Now · by Friday’s close)  
Sentence: "Long now: a 1% rise makes you $9.4K. The book stays long even if the market rises 10% by Friday, but Nike turns short above $36.23."  
Three numbers: $40K if up 5% · $3.4K flat to Friday · $52K if down 5%  
Cover: "Insurance puts cover 4,000 of your 15,000 shares, 27%. Shares have no floor below that."  
By name (1 short, 2 thin at a priced move):  
- Nike: Short above $36.23 by Friday · Short 917 Δ at ↑4.9%  
- Alibaba: Thin by Friday, never short · Thin at ↑5.6%  
- Netflix: Thin by Friday, never short · Thin at ↑6.3%  
- FIS: Stays long past ↑12.7% · Long 1,134 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 555 Δ at ↑2.5%  
- Uber: Stays long past ↑16.1% · Long 905 Δ at ↑5.4%  
- Lululemon: Stays long past ↑20.3% · Long 1,965 Δ at ↑6.8%


**open · Nicolay** (Now · by Friday’s close)  
Sentence: "Long now: a 1% rise makes you $2.8K. The book stays long even if the market rises 10% by Friday, but Nike turns short above $36.23."  
Three numbers: $12K if up 5% · $863 flat to Friday · $15K if down 5%  
Cover: "Insurance puts cover 1,200 of your 5,300 shares, 23%. Shares have no floor below that."  
By name (2 short at a priced move):  
- Nike: Short above $36.23 by Friday · Short 262 Δ at ↑4.9%  
- Alibaba: Short above $104.91 by Friday · Short 34 Δ at ↑5.6%  
- Netflix: Stays long past ↑19.0% · Long 383 Δ at ↑6.3%  
- FIS: Stays long past ↑12.7% · Long 454 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 208 Δ at ↑2.5%  
- Uber: Stays long past ↑16.1% · Long 377 Δ at ↑5.4%  
- Lululemon: Stays long past ↑20.3% · Long 517 Δ at ↑6.8%


**post · Sunny** (At the close · by Friday)  
Sentence: "Long now: a 1% rise makes you $9.5K. The book stays long even if the market rises 10% by Friday, but Nike turns short above $36.23."  
Three numbers: $40K if up 5% · $3.2K flat to Friday · $53K if down 5%  
Cover: "Insurance puts cover 4,000 of your 15,000 shares, 27%. Shares have no floor below that."  
By name (1 short, 2 thin at a priced move):  
- Nike: Short above $36.23 by Friday · Short 917 Δ at ↑4.9%  
- Alibaba: Thin by Friday, never short · Thin at ↑5.6%  
- Netflix: Thin by Friday, never short · Thin at ↑6.3%  
- FIS: Stays long past ↑12.7% · Long 1,134 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 555 Δ at ↑2.5%  
- Uber: Stays long past ↑16.1% · Long 905 Δ at ↑5.4%  
- Lululemon: Stays long past ↑20.3% · Long 1,965 Δ at ↑6.8%


**post · Nicolay** (At the close · by Friday)  
Sentence: "Long now: a 1% rise makes you $2.8K. The book stays long even if the market rises 10% by Friday, but Nike turns short above $36.23."  
Three numbers: $12K if up 5% · $799 flat to Friday · $15K if down 5%  
Cover: "Insurance puts cover 1,200 of your 5,300 shares, 23%. Shares have no floor below that."  
By name (2 short at a priced move):  
- Nike: Short above $36.23 by Friday · Short 262 Δ at ↑4.9%  
- Alibaba: Short above $104.91 by Friday · Short 34 Δ at ↑5.6%  
- Netflix: Stays long past ↑19.0% · Long 383 Δ at ↑6.3%  
- FIS: Stays long past ↑12.7% · Long 454 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 208 Δ at ↑2.5%  
- Uber: Stays long past ↑16.1% · Long 377 Δ at ↑5.4%  
- Lululemon: Stays long past ↑20.3% · Long 517 Δ at ↑6.8%


**weekend · Sunny** (Calls ended Friday · to next Friday)  
Sentence: "This week’s calls ended Friday, so you are long only until Monday’s sales: a 1% rise makes you $11K. Selling again brings the short back above the calls."  
Three numbers: $55K if up 5% · $1.2K flat to next Fri · $56K if down 5%  
Cover: "Insurance puts cover 4,000 of your 15,000 shares, 27%. Shares have no floor below that."  
By name (Every name long at a priced move):  
- Nike: Stays long past ↑14.8% · Long 6,291 Δ at ↑4.9%  
- Alibaba: Stays long past ↑16.9% · Long 2,237 Δ at ↑5.6%  
- Lululemon: Stays long past ↑20.3% · Long 1,969 Δ at ↑6.8%  
- Netflix: Stays long past ↑19.0% · Long 3,274 Δ at ↑6.3%  
- Uber: Stays long past ↑16.1% · Long 1,200 Δ at ↑5.4%  
- FIS: Stays long past ↑12.7% · Long 2,500 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 800 Δ at ↑2.5%


**weekend · Nicolay** (Calls ended Friday · to next Friday)  
Sentence: "This week’s calls ended Friday, so you are long only until Monday’s sales: a 1% rise makes you $3.3K. Selling again brings the short back above the calls."  
Three numbers: $16K if up 5% · $219 flat to next Fri · $17K if down 5%  
Cover: "Insurance puts cover 1,200 of your 5,300 shares, 23%. Shares have no floor below that."  
By name (Every name long at a priced move):  
- Nike: Stays long past ↑14.8% · Long 1,742 Δ at ↑4.9%  
- Alibaba: Stays long past ↑16.9% · Long 450 Δ at ↑5.6%  
- Lululemon: Stays long past ↑20.3% · Long 516 Δ at ↑6.8%  
- Netflix: Stays long past ↑19.0% · Long 982 Δ at ↑6.3%  
- Uber: Stays long past ↑16.1% · Long 500 Δ at ↑5.4%  
- FIS: Stays long past ↑12.7% · Long 1,000 Δ at ↑4.2%  
- PepsiCo: Stays long past ↑7.6% · Long 300 Δ at ↑2.5%

