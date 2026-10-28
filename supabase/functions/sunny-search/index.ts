/**
 * sunny-search · Sunny search (Nik, 27 Oct 2026; brief: https://claude.ai/artifact/9SbMGjPUaMpw1hvo4gSjo6;
 * launch design: handoff "Search for launch", block 27, 28 Oct 2026).
 *   POST { list: true }                     ->  the lookup menu
 *   POST { lookup, args? }                  ->  { card }: one lookup on its own
 *   POST { ask, thread?, deep?, stream? }   ->  { id, parts, source, follow_ups, recap, can_answer, check, cost_usd }
 *                                               stream: true sends one JSON line per step ({ step, work }) and the
 *                                               answer last ({ answer }), so the app can say what it is doing.
 *   POST { recents: true }                  ->  the caller's last 10 searches, newest first, each with what it gave
 *   POST { questions: true }                ->  the questions that work (typing suggestions) and the four Try chips
 *   POST { feedback: { id, value } }        ->  thumbs on an answer: up, down or not_asked
 * Answers are text at launch (no cards): a lead sentence, a big number or three numbers, lines, an explanation,
 * From the web, one panel per topic for an update on one name, or a plain "can't answer" (parts, below).
 * Numbers: the model never writes one. Every number a lookup returns reaches it named ("r12=99.63") and the answer
 * asks for it as [r12|$2] (slots.ts); Sunny writes the figure. The few digits typed by hand (dates, counts up to 20)
 * still go through the number check (check.ts): a miss gets one retry, then the words are withheld.
 * Asking: Claude Opus 5.5 at low effort; "Go deeper" (deep: true) at medium. Web search only when Sunny's data and
 * Nik's research cannot answer, always marked From the web with its sources. It reads; it never trades.
 * Every question is logged (search_log; the weekly misses are search_misses) and a book's spend is capped per day
 * (SEARCH_DAILY_USD, default $5). Who may call: the scheduler's x-cron-key, the service-role key, or a signed-in
 * member of a book (only that book; a member of two reads the one they own).
 */
import Anthropic from 'npm:@anthropic-ai/sdk@1.3.0';
import { caller, context, lookup, MENU, SB_KEY, SB_URL, type Ctx, type Row } from './lookups.ts';
import { checkAnswer } from './check.ts';
import { COUNTS, fmt, SLOT, Slots } from './slots.ts';

const BUILD = '2026-10-28.3';
const MODEL = 'claude-opus-5-5';
/** Test runs may still try Haiku on its own (step 4). */
const HAIKU = 'claude-haiku-5-5';
const MAX_STEPS = 8;
const client = new Anthropic();

// ── The tools: the lookups, and the web ──────────────────────────────────────────────────────────────────

const TOOLS: Row[] = [
  ...MENU.map((m) => ({
    name: m.name,
    description: m.shows,
    input_schema: { type: 'object', properties: m.args ?? {}, required: m.required ?? [], additionalProperties: false },
  })),
  { type: 'web_search_20260209', name: 'web_search', max_uses: 3,
    user_location: { type: 'approximate', country: 'US', timezone: 'America/New_York' } },
];

const SYSTEM = `You are the search in Sunny, Nik's options app. Nik runs an income book: deep in-the-money LEAPS calls on a
few names, a weekly call sold against each LEAPS at the money, hedge calls bought to stay delta positive up to +1.5 SD by
Thursday's close, insurance puts, and weekly puts sold only when the gates pass. Answer his question from his own data.

Reading:
- Always read with the lookups first, then answer. Never answer from memory, and never say you need to look something
  up: look it up.
- For walls, read gamma first: it has the tape's labels (Ceiling, Floor, Accelerator). Use walls_live only when gamma
  has no view for that ticker or expiry, and never give both sets of walls in one answer.
- Research (fundamentals, analyst_targets, earnings_history, research_notes) is what Nik saved from sources such as
  Investing Pro. It is context only: never let it change To do, strikes or hedges.
- web_search only when his data and research cannot answer: news, why a stock moved, company facts he has not saved.
  Never for his positions, walls, strikes, To do or prices: those are always Sunny's.
- You only read. You never place, change or cancel a trade; To do and its buttons are his.

Numbers, the hard rule: you never write a number yourself. Every number in the data reaches you named, like "r12=99.63".
Write a figure as a slot, [r12|$2], and Sunny fills it in. A slot may work a figure out from a few names: [r3-r5|$],
[r4/r9*100|%0], [abs(r2)|%]. The format after the bar:
  $ whole dollars ($1,140) · $2 to the cent, for prices ($99.63) · $k short ($3.8K, $46.3B)
  % one decimal (2.1%) · %0 whole (19%) · %2 two decimals (4.33%)
  # whole number (3,160) · #1 or #2 decimals (99.40) · d a delta (.62) · x a multiple (18.0x) · k a strike (104, 37.5)
A percent the data gives as a fraction needs *100. Signs never show: say fell, down, short or lose, and color it red.
The only digits you type yourself are dates (Oct 30), short years (Jan ’28) and counts up to 20 (3 days, ×15).

Words:
- Short, plain sentences, the answer first. No jargon he did not use, no em dashes, no hedging, no model names.
- Inside text: {b:x} bold for a number, {g:x} green for up, captured or kept, {r:x} red for down or short, {o:x} orange
  for thin. The slot goes inside: BABA fell {r:[r3|%]} to {b:[r1|$2]}.
- Dates as people say them: Oct 30, Dec 18, an expiry as Jan 15; only a LEAPS expiry carries its year, as Jan ’28.
  Never 2028-01-21.
- Name the period of any realized, interest or fee figure (since Aug 31, this month).

The shape: pick what fits, never more than the question needs.
- Lead with one "say" of two sentences at most. Then one "big" or one "trio", then "rows". A "big" only when the
  question asks for exactly one number; it then comes first, with a "body" sentence after it.
- "rows" for a list: a is the name or label, b the detail (start it with a space), r the number on the right.
- "body" for an explanation after the lead.
- A name's position (How's BABA?): a "say", then rows in this order. Sold: b " 104 calls ×15 · Oct 30", r captured %
  (up tone at 80% or more). LEAPS: b " 100 ×15 · Jan ’28", r "Δ .62" (thin tone under .70). Hedge: b " 110 calls ×10 ·
  Jan 15". Insurance: b " 95 puts ×5 · Jan 15". Delta: b " 19% of long · Thin", r "240 Δ" (tone by state). One row per
  To do order: a "To do" in thin tone, b " Buy 3 Jan 15 110 calls", r the amount (up tone when it comes in).
- A name's walls (BABA's walls this week): a "say", then rows from the highest strike down: a the strike (call or
  put tone), b " Ceiling ●●● · 0.4% above" (the label, its confidence as ●●● for 3, ●●○ for 2, ●○○ for 1, how far
  from the price, and "· your calls" when a sold strike sits there), r the gamma in $k with muted tone. In price
  order among them, a row with a the price and b " Today" (plain), and one with a the flip (muted) and b " Flip ·
  calmer above, choppier below". Then a "body" with the move the market prices by Friday. Source live.
- Panels only for an update on one name (give me an update on Nike, catch me up on BABA): a "say", a "trio" of three
  numbers, then one "panel" per topic, each with its own source: Your position, Walls this week, Fair value and
  targets, Valuation and dividend, Against peers and sector, The day after earnings. Leave out a panel when its data
  is not there.
- From the web: a "web" part (one or two sentences in words only, no figures, and the pages you used), then a "say"
  with Sunny's own figures on the name if it is in the book. Web words and Sunny's figures never share a part; source
  is then where Sunny's figures come from (the web part has its own line).
- When neither his data nor the web can answer: one "none" part (why, in one sentence, and did_you_mean, the nearest
  question that works) and can_answer false.
- Tones: up, down, thin, muted, call, put (call and put color a wall's strike); null is plain.
- source: where the answer's figures come from: sunny (positions, To do, yield, delta), live (gamma, walls, prices
  while the market is open), close (a price after the close), research (saved research), web.
- follow_ups: exactly two, short, the way he asks: "BABA's walls this week", "And for LULU?".
- Leave out any key whose value would be null.
- recap: one short line for his history list, slots allowed, no {b:} marks. With a big number: the few words that go
  under it ("collected · [r4|$] kept so far"). Otherwise the gist in one or two short sentences.

When you have read what you need, reply with only this JSON, no other text (parts in the order shown on screen):
{"parts": [
  {"say": "..."},
  {"big": {"label": "Calls sold this week", "value": "[r5|$]", "sub": "collected in premium"}},
  {"trio": [{"label": "Today", "value": "[r1|$2]", "sub": "[r3|%] today", "sub_tone": "down"}]},
  {"body": "..."},
  {"rows": {"head": "By name", "rows": [{"a": "NKE", "b": " 36 calls ×20 · Oct 30", "r": "[r9|%0]", "r_tone": "up"}]}},
  {"panel": {"title": "Fair value and targets", "say": "...", "rows": [{"a": "Fair value", "b": " · 15 models",
     "r": "[r7|$2]", "sub": "...", "bar": {"from": "[r8]", "to": "[r9]", "at": "[r7]"}}], "source": "research"}},
  {"web": {"summary": "...", "sources": [{"url": "https://...", "site": "Reuters"}]}},
  {"none": {"why": "...", "did_you_mean": "..."}}
 ],
 "source": "sunny", "follow_ups": ["...", "..."], "recap": "...", "can_answer": true}
A panel's table is {"cols": ["NKE", "Peers", "Sector"], "rows": [{"label": "Dividend yield", "values": ["[r1|%]", "[r2|%]",
"[r3|%]"], "tone": null}]}; a row's bar marks where "at" sits between "from" and "to".

Terms: captured % is how much of a sold option's premium is already earned. Walls are option strikes where dealers'
gamma piles up: a Ceiling or Floor tends to hold, an Accelerator speeds a move through it, Unclear has no clear read.
The flip is the price where dealer gamma turns from calming to amplifying. Net after hedges is premium sold, less what
was paid to close options, less this week's share of hedge costs. Insurance puts are long puts; hedge calls are long
calls that are not LEAPS. Delta figures are in shares unless a field says dollars. The value of calls (or puts) sold
is the premium collected for them; what they would cost to buy back is what is left, and the difference is kept.`;

const DEEP = `This is "Go deeper": Nik has the first answer (above) and wants the why behind it. Read more if it helps, then
answer with a "body" of two to four sentences that adds what the first answer left out, rows only if a list is the
point. Do not repeat the first answer. Same JSON, same rules.`;

// ── Time, for the source lines ───────────────────────────────────────────────────────────────────────────

const ET = (d: Date, o: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', ...o }).format(d);
const clock = (d: Date) => ET(d, { hour: 'numeric', minute: '2-digit' }).replace(/\u202f/g, ' ');
const dayMon = (iso: string) => { const d = new Date(String(iso).slice(0, 10) + 'T12:00:00Z');
  return Number.isNaN(+d) ? String(iso) : `${d.getUTCDate()} ${d.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' })}`; };
function marketOpen(d = new Date()): boolean {
  const wd = ET(d, { weekday: 'short' }), [h, m] = ET(d, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).split(':').map(Number);
  return !['Sat', 'Sun'].includes(wd) && h * 60 + m >= 570 && h * 60 + m < 960;
}
/** The session the last close belongs to: today after 4 PM on a weekday, else the weekday before. */
function lastClose(d = new Date()): string {
  const x = new Date(d);
  const [h] = ET(x, { hour: '2-digit', hourCycle: 'h23' }).split(':').map(Number);
  if (h < 16) x.setUTCDate(x.getUTCDate() - 1);
  while (['Sat', 'Sun'].includes(ET(x, { weekday: 'short' }))) x.setUTCDate(x.getUTCDate() - 1);
  return `${ET(x, { weekday: 'short' })} 4:00 PM`;
}

// ── Building the answer from what the model wrote ────────────────────────────────────────────────────────

interface Ran { name: string; args: Row; ok: boolean; ms: number; card?: Row; error?: string }
interface Seen { pages: Map<string, { title: string; age: string | null }>; cited: string[]; searches: number }

const TONES = new Set(['up', 'down', 'thin', 'muted', 'call', 'put']);
const tone = (x: unknown) => (typeof x === 'string' && TONES.has(x) ? x : null);
/** A search result's page date ("October 27, 2026") as 27 Oct; nothing when it is not a date. */
const ageOf = (x: string | null) => { const d = x ? new Date(x) : null; return d && !Number.isNaN(+d) ? dayMon(d.toISOString()) : null; };
const plain = (s: string) => s.replace(/\{[gbro]:([^}]*)\}/g, '$1');

/** The answer object from the model's last text: plain JSON, or JSON inside a code fence. */
function parseAnswer(text: string): Row | null {
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { const o = JSON.parse(m[0]); return Array.isArray(o.parts) ? o : null; } catch { return null; }
}

function sourceLine(kind: unknown, ran: Ran[], c: Ctx, seen: Seen, webN: number): Row | null {
  const k = String(kind ?? '');
  if (k === 'sunny') return { kind: 'sunny', text: `Sunny · updated ${clock(new Date(c.at))}` };
  if (k === 'live') {
    const oiOnly = ran.some((x) => x.ok && x.name === 'walls_live') && !ran.some((x) => x.ok && x.name === 'gamma');
    return { kind: 'live', text: oiOnly ? 'Live · OI only' : 'Live' };
  }
  if (k === 'close') return { kind: 'close', text: `Last close · ${lastClose()}` };
  if (k === 'research') {
    const src = ran.filter((x) => x.ok && x.card?.source?.kind === 'research').map((x) => x.card!.source)
      .sort((a, b) => String(b.asof).localeCompare(String(a.asof)))[0];
    return src ? { kind: 'research', text: `${String(src.source).split(',')[0]} · ${dayMon(src.asof)}` } : null;
  }
  if (k === 'web') return { kind: 'web', text: `From the web · ${webN || seen.pages.size} source${(webN || seen.pages.size) === 1 ? '' : 's'} · ${clock(new Date())}` };
  return null;
}

/** Turns the model's JSON into what the app shows: every slot written out, tones checked, web pages verified, and
    the text it typed by hand (slots taken out) gathered for the number check. */
function build(f: Row, sl: Slots, ran: Ran[], c: Ctx, seen: Seen) {
  const bad: string[] = [], lit: string[] = [], webLit: string[] = [];
  const S = (x: unknown, web = false): string | null => {
    if (x == null || x === '') return null;
    const t = String(x);
    (web ? webLit : lit).push(t.replace(SLOT, ' '));
    if (web && SLOT.test(t)) bad.push('Sunny figures in the web summary');
    SLOT.lastIndex = 0;
    return sl.fill(t, bad).replace(/ {2,}/g, ' ');
  };
  /** A bar's end or mark: one slot, as a plain number. */
  const N = (x: unknown): number | null => {
    const m = String(x ?? '').match(/^\s*\[([^\]|]+)(?:\|[^\]]*)?\]\s*$/);
    if (!m) return null;
    try { return sl.value(m[1]); } catch (e) { bad.push(`${x}: ${(e as Error).message}`); return null; }
  };
  const rows = (rs: unknown) => (Array.isArray(rs) ? rs : []).map((r: Row) => ({
    a: S(r.a), b: S(r.b), r: S(r.r), a_tone: tone(r.a_tone), b_tone: tone(r.b_tone), r_tone: tone(r.r_tone), sub: S(r.sub),
    bar: r.bar && typeof r.bar === 'object' ? (() => { const b = { from: N(r.bar.from), to: N(r.bar.to), at: N(r.bar.at) };
      return b.from != null && b.to != null && b.at != null ? b : null; })() : null,
  }));
  const trio = (xs: unknown) => (Array.isArray(xs) ? xs.slice(0, 3) : []).map((x: Row) => ({
    label: S(x.label), value: S(x.value), sub: S(x.sub), tone: tone(x.tone), sub_tone: tone(x.sub_tone) }));
  const parts: Row[] = [];
  let webN = 0;
  for (const p of (f.parts ?? []) as Row[]) {
    if (p.say) parts.push({ type: 'say', text: S(p.say) });
    else if (p.body) parts.push({ type: 'body', text: S(p.body) });
    else if (p.big) {
      const m = String(p.big.value ?? '').match(/^\s*\[([^\]|]+)(?:\|([^\]]*))?\]\s*$/);
      let n: number | null = null, value: string | null = null, f2 = '';
      if (m) { try { n = Math.abs(sl.value(m[1])); f2 = (m[2] ?? '').trim(); value = fmt(n, f2); } catch (e) { bad.push(`${p.big.value}: ${(e as Error).message}`); } }
      else value = S(p.big.value);
      parts.push({ type: 'big', label: S(p.big.label), value, n, count: n != null && COUNTS.has(f2), fmt: f2, sub: S(p.big.sub), tone: tone(p.big.tone) });
    } else if (p.trio) parts.push({ type: 'trio', items: trio(p.trio) });
    else if (p.rows) parts.push({ type: 'rows', head: S(p.rows.head), rows: rows(p.rows.rows) });
    else if (p.panel) {
      const q = p.panel, t = q.table && Array.isArray(q.table.rows) ? {
        cols: (q.table.cols ?? []).map((x: unknown) => String(x)).slice(0, 3),
        rows: q.table.rows.map((r: Row) => ({ label: S(r.label), values: (r.values ?? []).slice(0, 3).map((v: unknown) => S(v)), tone: tone(r.tone) })) } : null;
      parts.push({ type: 'panel', title: S(q.title), say: S(q.say), trio: q.trio ? trio(q.trio) : null, rows: q.rows ? rows(q.rows) : null,
        table: t, note: S(q.note), source: sourceLine(q.source, ran, c, seen, 0) });
    } else if (p.web) {
      // Only pages the search really returned; the title and date come from the search, not the model.
      const sources = (Array.isArray(p.web.sources) ? p.web.sources : []).map((s: Row) => {
        const pg = seen.pages.get(String(s.url ?? ''));
        return pg ? { site: String(s.site ?? new URL(String(s.url)).hostname.replace(/^www\./, '')), url: String(s.url),
          title: pg.title, date: ageOf(pg.age) } : null;
      }).filter(Boolean).slice(0, 4);
      webN = sources.length;
      parts.push({ type: 'web', summary: S(p.web.summary, true), sources, line: sourceLine('web', ran, c, seen, webN)!.text });
    } else if (p.none) parts.push({ type: 'none', why: S(p.none.why), did_you_mean: S(p.none.did_you_mean) });
  }
  // A big number leads (block 27): a sentence the model put above it moves under it, as body text.
  const bi = parts.findIndex((x) => x.type === 'big');
  if (bi > 0) {
    const [big] = parts.splice(bi, 1), before = parts.splice(0, bi).map((x) => (x.type === 'say' ? { ...x, type: 'body' } : x));
    parts.unshift(big, ...before);
  }
  const follow_ups = (Array.isArray(f.follow_ups) ? f.follow_ups : []).slice(0, 2).map((x: unknown) => plain(S(x) ?? '')).filter(Boolean);
  const recap = f.recap ? plain(S(f.recap) ?? '') : null;
  // The source line ends every answer, unless its last part is a panel with a source of its own.
  const last = parts.at(-1);
  const source = last?.type === 'panel' || last?.type === 'none' ? null : sourceLine(f.source ?? 'sunny', ran, c, seen, webN);
  return { parts, source, follow_ups, recap, can_answer: f.can_answer !== false && !parts.some((x) => x.type === 'none'),
    bad, literal: lit.join(' \n '), webLiteral: webLit.join(' \n ') };
}

const readData = (ran: Ran[]) => ran.filter((x) => x.ok && x.card).map((x) => x.card!.data);

/** What one lookup is doing, in words, for "Working it out"; work marks live data, research and the web. */
function stepOf(name: string, a: Row): { step: string; work: boolean } {
  const t = a.ticker ? String(a.ticker).toUpperCase() : '';
  const s = (step: string, work = false) => ({ step, work });
  switch (name) {
    case 'position': return s(`Reading your ${t} position`);
    case 'sold': return s(t ? `Reading what you sold on ${t}` : 'Reading what you sold');
    case 'bought': return s(t ? `Reading what you bought on ${t}` : 'Reading what you bought');
    case 'todo': return s('Reading To do');
    case 'delta_gamma': return s(t ? `Working out ${t}'s delta` : "Working out the book's delta");
    case 'gamma': return s(`Reading ${t}'s walls`, true);
    case 'walls_live': return s(`Reading ${t}'s live chain`, true);
    case 'yield': return s('Reading your yield');
    case 'payback': return s('Reading payback');
    case 'events': return s('Checking earnings and holidays');
    case 'fundamentals': case 'analyst_targets': case 'earnings_history': case 'research_notes':
      return s(`Reading saved research on ${t}`, true);
    case 'who_is_trading': return s(`Reading who trades ${t}`);
    case 'labels_held': return s(`Checking how ${t}'s walls held`, true);
    default: return s('Reading your book');
  }
}

// ── Asking ───────────────────────────────────────────────────────────────────────────────────────────────

/** Test runs only (step 4): force one model and effort for every question, and return everything each answer read. */
interface Test { model?: 'haiku' | 'opus'; effort?: 'low' | 'medium' | 'high'; trace?: boolean }
type Emit = (e: Row) => void;

async function ask(question: string, thread: Row[], deep: boolean, c: Ctx, owner: boolean, test: Test = {}, emit: Emit = () => {}) {
  const t0 = Date.now();
  const model = test.model === 'haiku' ? HAIKU : MODEL;
  const effort = test.effort ?? (deep ? 'medium' : 'low');
  const ran: Ran[] = [], sl = new Slots(), seen: Seen = { pages: new Map(), cited: [], searches: 0 };
  const usage = { input: 0, output: 0, cache_read: 0, cache_write: 0, web_searches: 0 };
  const names = Object.keys(c.p.plan ?? {}).sort().join(', ');
  const now = new Date();
  const messages: Row[] = [
    // Earlier questions in this thread, as plain text: "and for BABA?" carries on from them.
    ...thread.flatMap((x) => [{ role: 'user', content: String(x.q ?? '') }, { role: 'assistant', content: String(x.a ?? '') }]),
    { role: 'user', content: `Today is ${c.today}, ${clock(now)} New York time; the market is ${marketOpen(now) ? 'open' : 'closed'}. ` +
      `Names in the book: ${names}. Watchlist: ${(c.p.watchlist ?? []).map((w: Row) => w.ticker).join(', ') || 'none'}.\n\n` +
      `${deep ? DEEP + '\n\n' : ''}Question: ${question}` },
  ];
  let final: Row | null = null, built: ReturnType<typeof build> | null = null, stop = '', retried = false, firstMiss: string[] = [];
  let steps = 0;
  const step = (e: { step: string; work: boolean }) => { steps++; emit({ ...e, work: e.work || steps >= 3 }); };
  for (let i = 0; i < MAX_STEPS; i++) {
    const req: Row = {
      model, max_tokens: 16000, system: SYSTEM, tools: TOOLS, messages,
      cache_control: { type: 'ephemeral' },
      // No answer format while it reads: with one, Haiku answered before looking anything up (27 Oct 2026).
      output_config: { effort },
    };
    // Opus answers with Anthropic's server-side fallback on, so a declined answer is retried on another model.
    const s: any = model === MODEL
      ? client.beta.messages.stream({ ...req, betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' } as any)
      : client.messages.stream(req as any);
    for await (const ev of s) {
      if (ev.type === 'content_block_start' && ev.content_block?.type === 'server_tool_use') step({ step: 'Searching the web', work: true });
    }
    const r: Row = await s.finalMessage();
    usage.input += r.usage?.input_tokens ?? 0; usage.output += r.usage?.output_tokens ?? 0;
    usage.cache_read += r.usage?.cache_read_input_tokens ?? 0; usage.cache_write += r.usage?.cache_creation_input_tokens ?? 0;
    usage.web_searches += r.usage?.server_tool_use?.web_search_requests ?? 0;
    for (const b of r.content as Row[]) {
      if (b.type === 'web_search_tool_result' && Array.isArray(b.content))
        for (const x of b.content) if (x.url) seen.pages.set(String(x.url), { title: String(x.title ?? ''), age: x.page_age ?? null });
      if (b.type === 'text' && Array.isArray(b.citations)) for (const ci of b.citations) if (ci.cited_text) seen.cited.push(String(ci.cited_text));
    }
    stop = String(r.stop_reason);
    if (stop === 'refusal' || stop === 'max_tokens') break;
    messages.push({ role: 'assistant', content: r.content });
    if (stop === 'pause_turn') continue;
    const calls = (r.content as Row[]).filter((b) => b.type === 'tool_use');
    if (!calls.length) {
      final = parseAnswer((r.content as Row[]).filter((b) => b.type === 'text').map((b) => b.text).join(''));
      if (final) {
        built = build(final, sl, ran, c, seen);
        // THE NUMBER CHECK: a slot that names nothing, or a figure typed by hand that is not in the data, gets one retry.
        const ck = checkAnswer(built.literal, readData(ran), question);
        const wk = checkAnswer(built.webLiteral, [seen.cited.join(' ')]);
        const miss = [...built.bad, ...ck.unverified, ...wk.unverified.map((x) => `${x} (web)`)];
        if (miss.length && !retried) {
          retried = true; firstMiss = miss;
          messages.push({ role: 'user', content: `These figures do not come from the data: ${miss.join('; ')}. Every figure is a slot ` +
            'naming a number you read (or a sum of a few); web text has no figures. Answer again in the same JSON.' });
          final = null; built = null;
          continue;
        }
      }
      break;
    }
    // All of this turn's lookups at once, their results back in one message, every number named.
    const results = await Promise.all(calls.map(async (b) => {
      const s0 = Date.now(), args = (b.input ?? {}) as Row;
      step(stepOf(String(b.name), args));
      try {
        const card = await lookup(String(b.name), args, c, owner);
        ran.push({ name: b.name, args, ok: true, ms: Date.now() - s0, card });
        return { type: 'tool_result', tool_use_id: b.id, content: JSON.stringify({ ...card, data: sl.tag(card.data) }) };
      } catch (e) {
        const error = (e as Error).message;
        ran.push({ name: b.name, args, ok: false, ms: Date.now() - s0, error });
        return { type: 'tool_result', tool_use_id: b.id, content: error, is_error: true };
      }
    }));
    messages.push({ role: 'user', content: results });
  }

  // Not valid JSON at the end: one more short call puts what it wrote into the answer format.
  if (!final && (stop === 'end_turn' || stop === 'tool_use')) {
    try {
      const r: Row = await client.messages.create({ model, max_tokens: 6000, system: SYSTEM,
        messages: [...messages, { role: 'user', content: 'Give your final answer now: only the JSON object, in the answer format.' }],
        output_config: { effort: 'low' } } as any);
      usage.input += r.usage?.input_tokens ?? 0; usage.output += r.usage?.output_tokens ?? 0;
      final = parseAnswer((r.content as Row[]).filter((b) => b.type === 'text').map((b) => b.text).join(''));
      if (final) built = build(final, sl, ran, c, seen);
    } catch { /* falls through to "can't answer" */ }
  }

  const answered = !!built && stop !== 'refusal';
  // Still a figure it cannot back after the retry: the words are withheld.
  const ck = answered ? checkAnswer(built!.literal, readData(ran), question) : { ok: true, checked: 0, unverified: [] as string[] };
  const wk = answered ? checkAnswer(built!.webLiteral, [seen.cited.join(' ')]) : { ok: true, checked: 0, unverified: [] as string[] };
  const unverified = answered ? [...built!.bad, ...ck.unverified, ...wk.unverified] : [];
  const withheld = answered && unverified.length > 0;
  const none = (why: string): Row[] => [{ type: 'none', why, did_you_mean: null }];
  const parts = !answered ? none("That isn't in Sunny's data or on the sites Sunny trusts.")
    : withheld ? none("I couldn't check every figure in that answer against your data, so I've left it out.") : built!.parts;
  const lead = parts.find((p) => p.type === 'say' || p.type === 'body' || p.type === 'web');
  return {
    ok: true, build: BUILD, route: deep ? 'deeper' : 'quick', model, deep,
    parts,
    source: answered && !withheld ? built!.source : null,
    follow_ups: answered ? built!.follow_ups : [],
    recap: answered && !withheld ? built!.recap : null,
    can_answer: answered && !withheld ? built!.can_answer : false,
    check: { ok: !withheld, checked: ck.checked + wk.checked, unverified, retried, first_try_unverified: firstMiss },
    // For the test page and the step 4 harness, which read these.
    answer: lead ? plain(String(lead.text ?? lead.summary ?? '')) : String(parts[0]?.why ?? ''),
    big: (() => { const b = parts.find((p) => p.type === 'big'); return b ? { value: b.value, label: b.label } : null; })(),
    cards: [],
    lookups: ran.map(({ card: _c, ...x }) => x),
    ...(test.trace ? { read: ran.map((x) => ({ name: x.name, args: x.args, data: x.card?.data ?? null })) } : {}),
    usage, stop, effort, ms: Date.now() - t0,
  };
}

// ── The log, the cost and the daily guard ─────────────────────────────────────────────────────────────

/** Dollars per million tokens, input and output (cache reads 0.1x input, cache writes 1.25x input), and per search. */
const PRICE: Record<string, [number, number]> = { 'claude-opus-5-5': [4, 20], 'claude-haiku-5-5': [0.1, 0.5] };
const PER_SEARCH = 0.01;
const costOf = (model: string, u: Row) => {
  const p = PRICE[model] ?? PRICE[MODEL];
  return (u.input * p[0] + u.cache_read * p[0] * 0.1 + u.cache_write * p[0] * 1.25 + u.output * p[1]) / 1e6 + (u.web_searches ?? 0) * PER_SEARCH;
};
/** A day's ceiling on search spend for a book, on top of the console's monthly cap: a loop or a stuck page can never
    run up more than this. SEARCH_DAILY_USD overrides the $5 default. */
const DAILY_USD = Number(Deno.env.get('SEARCH_DAILY_USD') ?? '5');
const rest = (path: string, init: RequestInit = {}) => fetch(`${SB_URL}/rest/v1/${path}`, { ...init,
  headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
async function spentToday(book: string): Promise<number> {
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(new Date());
  const r = await rest(`search_log?book_id=eq.${book}&at=gte.${day}T04:00:00Z&select=cost_usd`);
  const rows = r.ok ? (await r.json()) as Row[] : [];
  return rows.reduce((s, x) => s + Number(x.cost_usd ?? 0), 0);
}
/** What the history list shows for an answer: its big number and the line under it, or its recap. */
function preview(a: Row): Row {
  const big = (a.parts as Row[]).find((p) => p.type === 'big');
  const line = a.recap ?? a.answer ?? '';
  return big ? { big: big.value, tone: big.tone, line } : { big: null, line };
}
async function logAsk(book: string, user: string | undefined, q: string, threadLen: number, deep: boolean, a: Row): Promise<number | null> {
  const r = await rest('search_log?select=id', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify([{
    book_id: book, user_id: user ?? null, question: q, thread_len: threadLen, deep, model: a.model, effort: a.effort,
    answer: a.answer, big: a.big, cards: (a.parts as Row[]).map((x) => x.type), lookups: a.lookups,
    parts: a.parts, source: a.source, recap: a.recap, preview: preview(a),
    can_answer: a.can_answer, check_ok: a.check?.ok ?? null, unverified: a.check?.unverified ?? [], retried: a.check?.retried ?? false,
    ms: a.ms, tokens: a.usage, cost_usd: Number(costOf(a.model, a.usage).toFixed(5)) }]) });
  if (!r.ok) { await r.body?.cancel(); return null; }
  return Number(((await r.json()) as Row[])[0]?.id ?? null);
}

/** The caller's last 10 searches across days: one row per question (asking again moves it up), newest first. */
async function recents(book: string, user: string | undefined): Promise<Row[]> {
  const who = user ? `user_id=eq.${user}` : 'user_id=is.null';
  const r = await rest(`search_log?book_id=eq.${book}&${who}&deep=is.false&select=id,at,question,preview,answer,big&order=at.desc&limit=80`);
  const rows = r.ok ? (await r.json()) as Row[] : [];
  const norm = (s: string) => s.toLowerCase().replace(/[’‘]/g, "'").replace(/[?!.\s]+$/, '').replace(/\s+/g, ' ').trim();
  const seenQ = new Set<string>(), out: Row[] = [];
  for (const x of rows) {
    const k = norm(String(x.question));
    if (seenQ.has(k)) continue;
    seenQ.add(k);
    out.push({ id: x.id, q: x.question, at: x.at, preview: x.preview ?? { big: x.big?.value ?? null, line: x.answer ?? '' } });
    if (out.length === 10) break;
  }
  return out;
}

/** The questions that work, for suggestions while typing, filled in with the book's names; and the four Try chips. */
function questions(c: Ctx): Row {
  const names = Object.keys(c.p.plan ?? {}).sort();
  const first = names.includes('NKE') ? 'NKE' : names[0] ?? 'BABA';
  const all = [
    'What do I need to do today?', 'How much time value is left in what I sold?', 'Which calls are 80% captured?',
    'How much did I make this week?', 'What did I pay for each LEAPS?', 'What is a Ceiling?', 'What is the flip?',
    'What’s the value of my calls sold?', 'What’s my delta right now?', 'Show all my sold positions', 'What changed today?',
    'Which hedges roll soon?', 'What earnings are coming up?', 'How is payback going?',
    ...names.flatMap((t) => [`How’s ${t}?`, `${t}’s walls this week`, `Give me an update on ${t}`, `What’s my sold position on ${t}?`,
      `What did ${t}’s bought legs cost?`, `How much time value is left on ${t}?`, `Why did ${t} move today?`, `Who is trading ${t}?`]),
  ];
  return { questions: all, tries: [`Give me an update on ${first}`, 'What’s the value of my calls sold?', 'What do I need to do today?', 'What’s my delta right now?'] };
}

const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  const who = await caller(req);
  if (!who) return json({ ok: false, error: 'not allowed' }, 401);
  let body: Row = {};
  if (req.method === 'POST') {
    const raw = await req.text();
    if (raw.trim()) { try { body = JSON.parse(raw); } catch { return json({ ok: false, error: 'body is not JSON' }, 400); } }
  }
  if (body.list) return json({ ok: true, build: BUILD, menu: MENU });
  try {
    // The scheduler and the service key may name a book; a signed-in user only ever reads their own.
    const book = who.system && body.book ? String(body.book) : who.book;
    if (body.lookup === '_key_check') {
      if (!who.owner) return json({ ok: false, error: 'not allowed' }, 401);
      const m = await client.models.retrieve(MODEL);
      return json({ ok: true, build: BUILD, model: m.id });
    }
    if (body.recents) return json({ ok: true, build: BUILD, recents: await recents(book, who.user) });
    const c = await context(book);
    if (body.questions) return json({ ok: true, build: BUILD, ...questions(c) });
    if (body.lookup) return json({ ok: true, build: BUILD, card: await lookup(String(body.lookup), body.args ?? {}, c, who.owner) });
    if (body.ask) {
      const q = String(body.ask).trim().slice(0, 1000);
      if (!q) return json({ ok: false, error: 'empty question' }, 400);
      const spent = await spentToday(book);
      const limited = spent >= DAILY_USD ? { ok: true, build: BUILD, parts: [{ type: 'none', why: `Today's search limit ($${DAILY_USD}) is reached. It resets at midnight.`, did_you_mean: null }],
        source: null, follow_ups: [], recap: null, can_answer: false, answer: `Today's search limit ($${DAILY_USD}) is reached.`, big: null, cards: [],
        limit: { daily_usd: DAILY_USD, spent_usd: Number(spent.toFixed(2)) } } : null;
      const thread = Array.isArray(body.thread) ? body.thread.slice(-6) : [];
      // Test settings only for the scheduler and service keys (the step 4 runs), never from the app.
      const run = async (emit?: Emit) => {
        const a = await ask(q, thread, !!body.deep, c, who.owner, who.system ? body.test ?? {} : {}, emit);
        const id = body.test ? null : await logAsk(book, who.user, q, thread.length, !!body.deep, a);
        return { ...a, id, cost_usd: Number(costOf(a.model, a.usage).toFixed(4)) };
      };
      if (!body.stream) return json(limited ?? await run());
      // Streamed: one JSON line per step, the answer last.
      const enc = new TextEncoder();
      return new Response(new ReadableStream({
        async start(ctl) {
          const send = (o: Row) => { try { ctl.enqueue(enc.encode(JSON.stringify(o) + '\n')); } catch { /* the app went away */ } };
          try { send({ answer: limited ?? await run(send) }); } catch (e) { send({ error: (e as Error).message }); }
          ctl.close();
        },
      }), { headers: { 'Content-Type': 'application/x-ndjson', 'Cache-Control': 'no-store' } });
    }
    // Thumbs on an answer: up, down, or "not what I asked"; only on the caller's own book.
    if (body.feedback) {
      const f = body.feedback as Row, value = String(f.value ?? '');
      if (!['up', 'down', 'not_asked', ''].includes(value) || !Number.isFinite(Number(f.id))) return json({ ok: false, error: 'bad feedback' }, 400);
      const r = await rest(`search_log?id=eq.${Number(f.id)}&book_id=eq.${book}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ feedback: value || null, feedback_at: value ? new Date().toISOString() : null }) });
      await r.body?.cancel();
      return json({ ok: r.ok, build: BUILD });
    }
    return json({ ok: false, error: 'send { ask }, { recents }, { questions }, { lookup }, or { list: true }' }, 400);
  } catch (e) {
    return json({ ok: false, build: BUILD, error: (e as Error).message }, 400);
  }
});
