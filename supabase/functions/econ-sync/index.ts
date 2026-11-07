/**
 * econ-sync: The economy and Out today on New Home (handoff 6 Nov 2026, Pass 2), from FRED.
 *
 * Twelve indicators (the design's sheet; series picked 4 Nov 2026, docs/econ-cards-sample.json). Each card
 * shows its latest reading and the three before it in its own rhythm (Nik, 4 Nov: "compare it to previous
 * data like last 3 quarters or 3 months... and see a trend"); a daily series uses each week's last value,
 * this week so far. The trend is the run of same-direction moves ending now ("Down 8 quarters in a row,
 * after 11 up"), plain ink arrows, no green or red.
 *
 * The read line and the "Worth watching" tag are RULES (Nik's rule 9: rules decide the facts and the tags):
 *   read  = how far back the reading is the highest or lowest (a year or more), and the change from a year ago;
 *   watch = it moved the worrying way this reading AND (it has for 2+ readings in a row, or it is the worst in
 *           a year); plus the yield curve below zero and the Sahm rule at 0.50 or more.
 * Each indicator's worrying way is fixed below (spreads, claims, late payments up; mood, credit growth down).
 *
 * Writes econ_cards (one row per indicator). landed_at = when this first saw the latest reading.
 * POST {} from pg_cron (x-cron-key). ⚠ DEPLOY WITH verify_jwt = false (cron sends a secret, not a JWT).
 * No em dashes in any words written here (Nik).
 */
const BUILD = '2026-11-07.2';

type Rhythm = 'week' | 'month' | 'quarter';
type Unit = 'pts' | 'signed' | 'people' | 'pct' | 'pct1' | 'growth' | 'index';
interface Def { id: string; series: string; title: string; rhythm: Rhythm; daily?: boolean; units?: string; unit: Unit; badUp: boolean;
  marker?: { label: string; value: number } }
const DEFS: Def[] = [
  { id: 'hy_spread', series: 'BAMLH0A0HYM2', title: 'Junk bond spread', rhythm: 'week', daily: true, unit: 'pts', badUp: true },
  { id: 'consumer_sentiment', series: 'UMCSENT', title: 'Consumer mood', rhythm: 'month', unit: 'index', badUp: false },
  { id: 'auto_delinquency', series: 'DROCLACBS', title: 'Auto and other loans', rhythm: 'quarter', unit: 'pct', badUp: true },
  { id: 'curve_10y3m', series: 'T10Y3M', title: 'Yield curve 10y minus 3m', rhythm: 'week', daily: true, unit: 'signed', badUp: false },
  { id: 'stress_index', series: 'STLFSI4', title: 'Financial stress', rhythm: 'week', unit: 'signed', badUp: true, marker: { label: 'Average', value: 0 } },
  { id: 'jobless_claims', series: 'ICSA', title: 'Jobless claims', rhythm: 'week', unit: 'people', badUp: true },
  { id: 'bank_credit', series: 'TOTBKCR', title: 'Bank credit growth', rhythm: 'week', units: 'pc1', unit: 'growth', badUp: false },
  { id: 'sahm', series: 'SAHMREALTIME', title: 'Sahm rule', rhythm: 'month', unit: 'pts', badUp: true, marker: { label: 'Recession signal', value: 0.5 } },
  { id: 'lending_standards', series: 'DRTSCILM', title: 'Banks tightening loans', rhythm: 'quarter', unit: 'pct1', badUp: true },
  { id: 'chargeoff_rate', series: 'QBPLNTLNNTCGOFFR', title: 'Loans written off', rhythm: 'quarter', unit: 'pct', badUp: true },
  { id: 'card_delinquency', series: 'DRCCLACBS', title: 'Credit cards behind on payments', rhythm: 'quarter', unit: 'pct', badUp: true },
  { id: 'debt_service', series: 'TDSP', title: 'Income spent on debt', rhythm: 'quarter', unit: 'pct1', badUp: true },
];

const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ymd = (d: string) => { const [y, m, dd] = d.split('-').map(Number); return { y, m, d: dd }; };
const mondayOf = (d: string) => { const x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() - ((x.getUTCDay() + 6) % 7)); return x.toISOString().slice(0, 10); };
const nyToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/New_York' });

function fmt(u: Unit, v: number): string {
  switch (u) {
    case 'pts': return v.toFixed(2);
    case 'signed': return `${v > 0 ? '+' : v < 0 ? '-' : ''}${Math.abs(v).toFixed(2)}`;
    case 'people': return v >= 1e6 ? `${(v / 1e6).toFixed(2)}M` : `${Math.round(v / 1000)}K`;
    case 'pct': return `${v.toFixed(2)}%`;
    case 'pct1': return `${v.toFixed(1)}%`;
    case 'growth': return `${v > 0 ? '+' : v < 0 ? '-' : ''}${Math.abs(v).toFixed(1)}%`;
    case 'index': return v.toFixed(1);
  }
}
/** A change, in words that fit the unit ("0.79", "12K", "0.3 points"). */
function fmtBy(u: Unit, v: number): string {
  const a = Math.abs(v);
  switch (u) {
    case 'people': return a >= 1e6 ? `${(a / 1e6).toFixed(2)}M` : `${Math.round(a / 1000)}K`;
    case 'pct': case 'pct1': case 'growth': return `${a.toFixed(u === 'pct' ? 2 : 1)} points`;
    case 'index': return a.toFixed(1);
    default: return a.toFixed(2);
  }
}

interface Pt { period: string; label: string; value: number }
/** Observations in the card's rhythm. A daily series: each week's last value, the current week labelled "This week". */
function inRhythm(def: Def, obs: { date: string; value: number }[], today: string): Pt[] {
  if (def.daily) {
    const byWeek = new Map<string, { date: string; value: number }>();
    for (const o of obs) byWeek.set(mondayOf(o.date), o);
    const thisWeek = mondayOf(today);
    return [...byWeek].sort((a, b) => a[0].localeCompare(b[0])).map(([w, o]) => ({ period: o.date, label: w === thisWeek ? 'This week' : `${MON[ymd(o.date).m - 1]} ${ymd(o.date).d}`, value: o.value }));
  }
  return obs.map((o) => {
    const x = ymd(o.date);
    const label = def.rhythm === 'quarter' ? `Q${Math.floor((x.m - 1) / 3) + 1} ${x.y}` : def.rhythm === 'month' ? MON[x.m - 1] : `${MON[x.m - 1]} ${x.d}`;
    return { period: o.date, label, value: o.value };
  });
}

/** The run of same-direction moves ending at the latest, and the run before it. */
function runs(pts: Pt[]) {
  const dir = (i: number) => Math.sign(pts[i].value - pts[i - 1].value);
  const n = pts.length;
  if (n < 2) return { d: 0, k: 0, d2: 0, k2: 0 };
  const d = dir(n - 1);
  let k = 0, i = n - 1;
  while (i >= 1 && dir(i) === d) { k++; i--; }
  const d2 = i >= 1 ? dir(i) : 0;
  let k2 = 0;
  while (i >= 1 && dir(i) === d2 && d2 !== 0) { k2++; i--; }
  return { d, k, d2, k2 };
}
function trendLine(def: Def, pts: Pt[]): string {
  const { d, k, d2, k2 } = runs(pts), per = def.rhythm;
  const w = (x: number) => (x > 0 ? 'up' : 'down'), W = (x: number) => (x > 0 ? 'Up' : 'Down');
  if (d === 0) return `Unchanged this ${per}`;
  if (k === 1 && k2 >= 2) return `${d > 0 ? 'Rose' : 'Dipped'} this ${per} after ${k2} ${per}s ${w(d2)}`;
  if (k === 1) return `${W(d)} this ${per}`;
  return `${W(d)} ${k} ${per}s in a row${k2 >= 2 ? `, after ${k2} ${w(d2)}` : ''}`;
}
/** How many points make a year in this rhythm. */
const yearN = (r: Rhythm) => (r === 'week' ? 52 : r === 'month' ? 12 : 4);
const monYear = (d: string) => `${MON[ymd(d).m - 1]} ${ymd(d).y}`;

function readLine(def: Def, pts: Pt[]): { note: string; worst: boolean } {
  const n = pts.length, last = pts[n - 1], yn = yearN(def.rhythm);
  const bits: string[] = [];
  // How far back it is the highest or lowest (a year or more).
  let worst = false;
  for (const hi of [true, false]) {
    let j = n - 2;
    while (j >= 0 && (hi ? pts[j].value < last.value : pts[j].value > last.value)) j--;
    const span = j < 0 ? n - 1 : n - 1 - j;
    if (span >= yn) {
      bits.push(j < 0 ? `The ${hi ? 'highest' : 'lowest'} in at least ${Math.floor((n - 1) / yn)} years.` : `The ${hi ? 'highest' : 'lowest'} since ${monYear(pts[j].period)}.`);
      if (hi === def.badUp) worst = true;
    }
  }
  if (n > yn) {
    const ago = pts[n - 1 - yn], ch = last.value - ago.value;
    const by = fmtBy(def.unit, ch);
    bits.push(!/[1-9]/.test(by) ? 'About the same as a year ago.' : `${ch > 0 ? 'Up' : 'Down'} ${by} from a year ago.`);
  }
  return { note: bits.join(' '), worst };
}

async function fred(path: string, key: string): Promise<any> {
  const r = await fetch(`https://api.stlouisfed.org/fred/${path}&api_key=${key}&file_type=json`, { signal: AbortSignal.timeout(20_000) });
  if (!r.ok) throw new Error(`fred ${path.split('?')[0]} ${r.status}`);
  return await r.json();
}

async function callerOk(req: Request): Promise<boolean> {
  const cron = Deno.env.get('CRON_SECRET');
  if (cron && (req.headers.get('x-cron-key') === cron || req.headers.get('x-admin-key') === cron)) return true;
  return (req.headers.get('authorization') ?? '') === `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`;
}

Deno.serve(async (req) => {
  if (req.method !== 'OPTIONS' && !(await callerOk(req))) return new Response(JSON.stringify({ ok: false, error: 'not allowed' }), { status: 401 });
  const url = Deno.env.get('SUPABASE_URL')!, sk = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, key = Deno.env.get('FRED_API_KEY')!;
  const H = { apikey: sk, Authorization: `Bearer ${sk}`, 'Content-Type': 'application/json' };
  const today = nyToday();
  const start = `${Number(today.slice(0, 4)) - 4}${today.slice(4)}`;
  const saved = new Map<string, any>((await (await fetch(`${url}/rest/v1/econ_cards?select=id,last_period,landed_at`, { headers: H })).json() as any[]).map((r) => [r.id, r]));
  const rows: any[] = [], errors: string[] = [];
  for (const [ord, def] of DEFS.entries()) {
    try {
      const meta = (await fred(`series?series_id=${def.series}`, key))?.seriess?.[0];
      const obs = ((await fred(`series/observations?series_id=${def.series}&observation_start=${start}${def.units ? `&units=${def.units}` : ''}`, key))?.observations ?? [])
        .filter((o: any) => o.value !== '.' && Number.isFinite(Number(o.value))).map((o: any) => ({ date: String(o.date), value: Number(o.value) }));
      const pts = inRhythm(def, obs, today);
      if (pts.length < 4) throw new Error(`${def.series}: ${pts.length} points`);
      const last = pts[pts.length - 1], prev = pts[pts.length - 2], four = pts.slice(-4);
      const { d, k } = runs(pts), badWay = def.badUp ? d > 0 : d < 0;
      const { note, worst } = readLine(def, pts);
      const watch = (badWay && (k >= 2 || worst)) || (def.id === 'curve_10y3m' && last.value < 0) || (def.id === 'sahm' && last.value >= 0.5);
      // The year's worst, marked on the chart when it is not among the four shown.
      const yr = pts.slice(-yearN(def.rhythm));
      const w = yr.reduce((a, p) => ((def.badUp ? p.value > a.value : p.value < a.value) ? p : a), yr[0]);
      const marker = def.marker ? `${def.marker.label} · ${fmt(def.unit, def.marker.value)}`
        : !four.some((p) => p.period === w.period) ? `${w.label}${def.rhythm !== 'quarter' && w.period.slice(0, 4) !== today.slice(0, 4) ? ` ’${w.period.slice(2, 4)}` : ''} ${def.badUp ? 'high' : 'low'} · ${fmt(def.unit, w.value)}` : undefined;
      const card = {
        id: def.id, name: def.title, label: def.title, value: fmt(def.unit, last.value),
        arrow: last.value > prev.value ? '↗' : last.value < prev.value ? '↘' : '→', trend: trendLine(def, pts),
        chartAria: `${def.title}: ${four.map((p) => `${p.label} ${fmt(def.unit, p.value)}`).join(', ')}`,
        chart: { points: four.map((p, i) => ({ label: p.label, value: fmt(def.unit, p.value), current: i === 3 })), ...(marker ? { marker } : {}) },
        note, period: last.period, series: def.series,
      };
      const was = saved.get(def.id);
      const fredUpdated = meta?.last_updated ? new Date(String(meta.last_updated).replace(' ', 'T').replace(/([+-]\d\d)$/, '$1:00')).toISOString() : null;
      const landed = was && was.last_period === last.period && was.landed_at ? was.landed_at : (was ? new Date().toISOString() : fredUpdated ?? new Date().toISOString());
      rows.push({ id: def.id, ord, series: def.series, title: def.title, rhythm: def.rhythm, card, watch, last_period: last.period,
        fred_updated: fredUpdated, landed_at: landed, updated_at: new Date().toISOString() });
    } catch (e) { errors.push(String((e as Error)?.message ?? e)); }
  }
  if (rows.length) {
    const w = await fetch(`${url}/rest/v1/econ_cards?on_conflict=id`, { method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify(rows) });
    if (!w.ok) errors.push(`write ${w.status} ${(await w.text()).slice(0, 160)}`);
  }
  await fetch(`${url}/rest/v1/sync_heartbeat?on_conflict=feed`, { method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify([{ feed: 'econ-sync', ran_at: new Date().toISOString(), rows_written: rows.length,
      detail: `${BUILD} · ${rows.length}/${DEFS.length} cards${errors.length ? ` · ${errors.join('; ').slice(0, 300)}` : ''}` }]) });
  return new Response(JSON.stringify({ ok: !errors.length, build: BUILD, cards: rows.length, watch: rows.filter((r) => r.watch).map((r) => r.id), errors }),
    { headers: { 'Content-Type': 'application/json' } });
});
