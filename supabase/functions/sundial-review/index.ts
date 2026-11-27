/**
 * sundial-review: the written review (Nik, 27 Nov 2026: "another layer of audit, almost like a managerial layer"; part
 * 3 of the inspection). Once a trading day, right after the inspection, Claude reads the spec (docs/SUNDIAL.md), the
 * engine's answer for every name, the board, the inspection and the day's 10/12/2/4 checks, and writes one plain line
 * per name, plus anything worth a look: a rule not followed, a number that does not add up, stale data, or a sale the
 * rules allow that looks risky today (a big jump or drop, momentum, IV, earnings, delta turning short).
 *
 * It never changes what Sundial suggests. It saves the review on the inspection's row (sundial_inspections.review) and
 * pushes Nik only when something is worth a look.
 *
 * POST { id }                review that inspection (the inspector sends this after a scheduled run); answers at once,
 *                            the review runs in the background
 * POST { id?, wait: true }   review (the latest inspection if no id) and answer with it: for testing by hand, and only
 *                            when it finishes inside the server's 150 s (a review takes about 1 to 3 minutes)
 *
 * ⚠ DEPLOY WITH verify_jwt = false: callers send x-cron-key (vault cron_secret). Files: index.ts, spec.ts (made by
 * make_spec.py from docs/SUNDIAL.md). No em dashes in any words here.
 */
import Anthropic from 'npm:@anthropic-ai/sdk@1.3.0';
import { SPEC } from './spec.ts';

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };
const URL_ = Deno.env.get('SUPABASE_URL')!;
const SK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const NIK = '85dd190f-9381-4acf-b123-7f1f6f778947';
const BUILD = '2026-11-27.3';
const MODEL = 'claude-opus-5-5';
// Medium: at high it spent all 16,000 tokens thinking and wrote nothing (27 Nov, first run, 164 s).
const EFFORT = 'medium';
type Row = Record<string, any>;
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
const client = new Anthropic();

// ── Data ──
const db = async (path: string): Promise<Row[]> => {
  const r = await fetch(`${URL_}/rest/v1/${path}`, { headers: { apikey: SK, Authorization: `Bearer ${SK}` } });
  if (!r.ok) { await r.body?.cancel(); return []; }
  return await r.json() as Row[];
};
const write = async (method: string, path: string, body: unknown, prefer: string) => {
  const r = await fetch(`${URL_}/rest/v1/${path}`, { method, headers: { apikey: SK, Authorization: `Bearer ${SK}`, 'Content-Type': 'application/json', Prefer: prefer }, body: JSON.stringify(body) });
  await r.body?.cancel(); return r.ok;
};
async function engine(body: Row): Promise<Row> {
  const r = await fetch(`${URL_}/functions/v1/sundial`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-cron-key': Deno.env.get('CRON_SECRET') ?? '' }, body: JSON.stringify(body) });
  return r.ok ? await r.json() : { error: `sundial ${r.status}` };
}
const r2 = (x: number) => Math.round(x * 100) / 100;
const pct = (a: number, b: number) => (b > 0 ? r2((a / b - 1) * 100) : null);

// ── What Claude reads ──
/** One name, kept to what a reviewer needs (the engine's full answer carries every banked leg). */
function nameIn(n: Row, card: Row | null, insp: Row | null, audits: Row[], closes: Row[], pxAt: Map<string, Row>[]) {
  const seq = closes.map((c) => Number(c.close_price)).reverse();   // oldest first, the last 6 sessions before today
  return {
    t: n.t, book: n.book, settings: { testUp: n.up, cadence: n.cad, ...n.cfg },
    price: { now: n.S, prevClose: n.prevClose, dayPct: pct(n.S, n.prevClose), estimated: n.est,
      last6Closes: seq, fiveDayPct: seq.length >= 5 ? pct(n.S, seq[seq.length - 5]) : null },
    reads: n.signals, reason: n.reason, earnings: n.earnings, target: n.target, saleDay: n.saleDay,
    plan: n.plan, test: n.test, holds: n.holds, drop: n.drop,
    soldToday: (n.todays ?? []).map((x: Row) => `${x.action} ${x.side < 0 ? 'sold' : 'bought'} ${x.n} $${x.K} ${x.type}s ${x.ex} at $${x.px} (${String(x.at).slice(11, 16)} UTC)`),
    open: { working: n.working, close: n.close, expiring: n.expiring },
    keptThisMonth: n.monthKept,
    board: card ? { toSell: card.toSell?.cards ?? [], drops: card.drops ?? [], close: card.close?.cards ?? [] } : null,
    inspection: insp ? { problems: insp.problems, notes: insp.notes, checks: insp.checks } : null,
    checksToday: audits.map((a, i) => { const x = (a.results as Row[]).find((y) => y.t === n.t); const q = pxAt[i]?.get(n.t);
      return x ? { slot: a.slot, price: q ? r2(Number(q.spot)) : null, dayPct: q ? r2(Number(q.day_change_pct)) : null, problems: x.problems, notes: x.notes, suggested: x.suggested, test: x.test } : null; }).filter(Boolean),
  };
}

const SYSTEM = `You are the manager who reviews Sundial once a day. Sundial is Nik's selling engine: it decides only which calls and puts to sell, and Nik decides what to buy. Its rules are Nik's, agreed one at a time, and written in the spec below. You do not make new rules and you never tell Nik to trade. You check that today's answers follow the spec, that the numbers add up, and that nothing looks risky that the rules alone would miss.

Two checks have already run today, and you are given what they found:
- The check at 10 AM, 12 PM, 2 PM and 4 PM rebuilds each book from IBKR's trades a second way and asks whether the board is over or under suggesting.
- The inspection works every name out again with its own code (its own option maths, data reads and count search) and compares.
Their problems are things a rule says is wrong; their notes are facts worth knowing. Each check carries every name's price when it ran: when a book's loss at the test size grows from one check to the next, compare the prices first. A book that fails its test because the price rose after the sales is expected, and the engine then suggests nothing more on it; say it as a fact, not a fault.

The rules decide what Sundial suggests, not what Nik does. Nik also trades by hand: hedge calls and puts, long puts paid for by sold puts (his put cover programme), and strikes of his own choosing. The put cap stops Sundial suggesting more puts; it does not limit Nik. A hand trade is never a rule broken. Mention one only when it changes the risk, as a fact ("40 $130 puts Nik sold by hand are open"), kind "judgement". Explain each problem in plain words and say whether it is real or a timing effect (IBKR sends a fill a few minutes after it happens; after the close the board shows the plan that locked 15 minutes before it).

For every name, look at:
1. Delta: the book should be delta positive now. Say what +1 weekly SD does to it.
2. The test: the name's own size (testUp). Is the book inside it, and do the suggestions keep it there?
3. Market factors: the index move today, the name's move today and over five sessions, the reads (week's move in SD, trend against the 50 and 200 day, IV rich or cheap, IV against the last 20 days' real moves), earnings.
4. Big drops: the 2 daily SD line (and TLT's 3 daily SD line). Is the price near or under it, and did the engine act?
5. Momentum: selling calls the day after a big jump, or puts into a slide, is allowed by the rules but worth saying.
6. The numbers: strikes, counts and credits agree between the engine, the board and the inspection.

Write the way Nik reads:
- Short sentences, plain words, the answer first. No jargon he did not use. Say "a normal week's move" the first time you say SD.
- Tickers only (SPCX, never the company name). No em dashes. Use + and - signs for moves and money ($+1.2K, -3%).
- Quote numbers from the data; do not invent any. If you work one out, keep it simple (a difference or a percent).
- One line per name, at most 25 words. Most days most names are fine: say so in a few words.
- "look" items are only for things Nik should see today. Each has a kind: "rule" (the spec was not followed), "numbers" (something does not add up), "data" (stale or missing), "judgement" (the rules allow it but today it looks risky). Never more than 5.

Answer with only this JSON, nothing before or after it:
{"verdict":"fine"|"look","summary":"one or two sentences","names":[{"t":"NVDA","status":"fine"|"look","line":"..."}],"look":[{"t":"NVDA","kind":"rule"|"numbers"|"data"|"judgement","what":"one sentence","why":"one sentence"}]}

The spec (docs/SUNDIAL.md):
<spec>
${SPEC}
</spec>`;

function parse(text: string): Row | null {
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { const o = JSON.parse(m[0]); return Array.isArray(o.names) ? o : null; } catch { return null; }
}
const COST: [number, number] = [4, 20];   // dollars per million tokens in and out (cache reads 0.1x, writes 1.25x)
const costOf = (u: Row) => ((u.input_tokens ?? 0) * COST[0] + (u.cache_read_input_tokens ?? 0) * COST[0] * 0.1 +
  (u.cache_creation_input_tokens ?? 0) * COST[0] * 1.25 + (u.output_tokens ?? 0) * COST[1]) / 1e6;

async function review(insp: Row) {
  const t0 = Date.now(), day = String(insp.day);
  const [view, board, audits, ...idx] = await Promise.all([engine({ mode: 'view' }), engine({ mode: 'board', account: 'ab', name: 'all' }),
    db(`sundial_audits?day=eq.${day}&order=run_at.asc&select=slot,run_at,problems,results`),
    ...['SPY', 'QQQ', 'IWM'].map((t) => db(`ticker_quotes?ticker=eq.${t}&order=captured_at.desc&limit=1&select=ticker,day_change_pct,captured_at`))]);
  const names: Row[] = view.names ?? [];
  const tk = names.map((n) => n.t).join(',');
  const [closes, pxAt] = await Promise.all([
    Promise.all(names.map((n) => db(`daily_closes?ticker=eq.${n.t}&date=lt.${day}&order=date.desc&limit=12&select=date,close_price`))),
    // every name's price when each check ran (the nearest quote within a minute either side)
    Promise.all(audits.map(async (a) => {
      const at = Date.parse(String(a.run_at)), lo = new Date(at - 60_000).toISOString(), hi = new Date(at + 60_000).toISOString();
      const rows = await db(`ticker_quotes?ticker=in.(${tk})&captured_at=gte.${lo}&captured_at=lte.${hi}&order=captured_at.desc&select=ticker,spot,day_change_pct`);
      const m = new Map<string, Row>(); for (const r of rows) if (!m.has(r.ticker)) m.set(r.ticker, r); return m;
    })),
  ]);
  // sessions only: a close stored on a holiday is not a session
  const cal = await db(`market_calendar?kind=eq.closed&date=gte.${new Date(Date.parse(day) - 30 * 864e5).toISOString().slice(0, 10)}&select=date`);
  const shut = new Set(cal.map((r) => String(r.date)));
  const sess = closes.map((rs) => rs.filter((r) => !shut.has(String(r.date))).slice(0, 6));
  const inspBy = new Map<string, Row>(((insp.results ?? []) as Row[]).map((r) => [String(r.t), r]));
  const ny = new Date(new Date().toLocaleString('en-US', { timeZone: 'America/New_York' }));
  const input = {
    today: day, nyTime: `${ny.getHours()}:${String(ny.getMinutes()).padStart(2, '0')}`, marketOpen: view.open, closesAt: view.closesAt,
    planLocksAt: board.finalAt, boardFinal: board.final, engineBuild: view.build,
    indexes: idx.map((r) => r[0]).filter(Boolean).map((q) => ({ t: q.ticker, dayPct: r2(Number(q.day_change_pct)) })),
    inspection: { at: insp.at_mins != null ? `${Math.floor(insp.at_mins / 60)}:${String(insp.at_mins % 60).padStart(2, '0')}` : null, problems: insp.problems, forced: insp.forced },
    checksToday: audits.map((a) => ({ slot: a.slot, problems: a.problems })),
    names: names.map((n, i) => nameIn(n, board.views?.[n.t] ?? null, inspBy.get(n.t) ?? null, audits, sess[i], pxAt)),
    otherFindings: ((insp.results ?? []) as Row[]).filter((r) => !names.some((n) => n.t === r.t)),
  };
  const ask = async (effort: string) => {
    const s: any = client.messages.stream({
      model: MODEL, max_tokens: 32000, system: SYSTEM,
      thinking: { type: 'adaptive' }, output_config: { effort },
      messages: [{ role: 'user', content: `Today's data, as JSON:\n${JSON.stringify(input)}\n\nWrite today's review.` }],
    } as any);
    const msg: Row = await s.finalMessage();
    return { msg, text: (msg.content as Row[]).filter((b) => b.type === 'text').map((b) => b.text).join('') };
  };
  let effort = EFFORT, { msg, text } = await ask(effort), out = parse(text), cost = costOf(msg.usage ?? {});
  // Ran out of room or wrote no JSON: once more at low effort, which thinks less.
  if (!out) { effort = 'low'; ({ msg, text } = await ask(effort)); out = parse(text); cost += costOf(msg.usage ?? {}); }
  const rv: Row = {
    build: BUILD, model: MODEL, effort, ms: Date.now() - t0, stop: msg.stop_reason, usage: msg.usage,
    cost_usd: Number(cost.toFixed(4)),
    ...(out ?? { verdict: 'error', summary: 'The review could not be read.', names: [], look: [], raw: text.slice(0, 4000) }),
  };
  await write('PATCH', `sundial_inspections?id=eq.${insp.id}`, { review: rv, review_at: new Date().toISOString() }, 'return=minimal');
  if (!insp.forced && rv.verdict === 'look' && Array.isArray(rv.look) && rv.look.length) {
    const lines = (rv.look as Row[]).slice(0, 3).map((l) => `${l.t}: ${l.what}`);
    await write('POST', 'alert_dispatch?on_conflict=dedup_key', [{ category: 'sundial', dedup_key: `sundial:review:${day}`, ticker: null,
      title: `Sundial review: ${rv.look.length} to look at`, body: lines.join(' '), deep_link: null, book_id: 'S',
      meta: { user_id: NIK, src: 'sundial-review', inspection: insp.id } }], 'resolution=ignore-duplicates,return=minimal');
  }
  return rv;
}

Deno.serve(async (req) => {
  const cron = Deno.env.get('CRON_SECRET');
  if (!cron || (req.headers.get('x-cron-key') !== cron && req.headers.get('x-admin-key') !== cron)) return json(401, { error: 'not allowed' });
  const body = await req.json().catch(() => ({})) as Row;
  const rows = body.id ? await db(`sundial_inspections?id=eq.${Number(body.id)}&select=*`)
    : await db(`sundial_inspections?order=id.desc&limit=1&select=*`);
  const insp = rows[0];
  if (!insp) return json(404, { build: BUILD, error: 'no inspection' });
  const job = review(insp).catch(async (e) => {
    const rv = { build: BUILD, verdict: 'error', summary: String((e as Error)?.message ?? e).slice(0, 500), names: [], look: [] };
    await write('PATCH', `sundial_inspections?id=eq.${insp.id}`, { review: rv, review_at: new Date().toISOString() }, 'return=minimal');
    return rv;
  });
  if (body.wait) return json(200, { build: BUILD, id: insp.id, review: await job });
  try { EdgeRuntime.waitUntil(job); } catch { await job; }
  return json(202, { build: BUILD, id: insp.id, review: 'started' });
});
