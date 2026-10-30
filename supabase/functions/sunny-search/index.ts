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
import { caller, context, db, lookup, MENU, SB_KEY, SB_URL, type Ctx, type Row } from './lookups.ts';
import { checkAnswer } from './check.ts';
import { COUNTS, fmt, SLOT, Slots } from './slots.ts';

const BUILD = '2026-10-30.10';
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
- A name's position (How's BABA?): a "say", then {"chart": true} (read chart, range w), then rows in this order. Sold: b " 104 calls ×15 · Oct 30", r captured %
  (up tone at 80% or more); when worth_more_than_sold_pct is there instead, the calls are worth more than they were sold
  for: r is that % in down tone, b ends " · worth more than sold", and nothing calls it captured. LEAPS: b " 100 ×15 · Jan ’28", r "Δ .62" (thin tone under .70). Hedge: b " 110 calls ×10 ·
  Jan 15". Insurance: b " 95 puts ×5 · Jan 15". Delta: b " 19% of long · Thin", r "240 Δ" (tone by state). One row per
  To do order: a "To do" in thin tone, b " Buy 3 Jan 15 110 calls", r the amount (up tone when it comes in).
- A name's walls (BABA's walls this week): a "say", then {"chart": true} (read chart, range w), then rows from the
  highest strike down: a the strike (call or
  put tone), b " Ceiling ●●● · 0.4% above" (the label, its confidence as ●●● for 3, ●●○ for 2, ●○○ for 1, how far
  from the price, and "· your calls" when a sold strike sits there), r the gamma in $k with muted tone. In price
  order among them, a row with a the price and b " Today" (plain), and one with a the flip (muted) and b " Flip ·
  calmer above, choppier below". Then a "body" with the move the market prices by Friday. Source live.
- Rolling a name's calls, or how much delta a name needs (I want to roll my Nike calls, what should I do? How much
  delta do I need on NKE?): read roll and tell it as a story, in this order. Never pick, rank or suggest: no "buy",
  "should", "best", "cheapest" or "I'd". Nik decides.
  1. A "say": the roll and what it leaves, its number always delta_needed (the same number as step 3): "Rolling 60
     NKE calls to Nov 6 at $37.50 leaves you about {r:890} delta short by Thursday." When delta_needed is 0: covered,
     with the lowest delta to spare in green. In an earnings week no calls are sold: say that instead of the roll.
  2. A "body" for each, one or two sentences, starting with the bold word: {b:Sold.} what the calls carry now and
     what they could be if the price reaches the target by Thursday (say the price and the SD); {b:Bought.} the
     LEAPS and hedge calls (and shares) now and at the target; {b:Insurance.} what the puts take away now and at the
     target (leave out when none); {b:Net.} the net now and at the target, and when lowest_on_the_way is lower, that
     it dips to that delta at that price.
  3. A "body": "You need about [delta_needed] more delta. Here's what each month adds." (covered: "Here's what each
     month would add.")
  4. Then {"roll_months": true}: Sunny adds one panel per month (its walls, the calls that would cover the delta
     needed and their cost) and a last one for shares. Write nothing about the months yourself.
  follow_ups such as "NKE's walls in January", "And for BABA?".
- Payoff by Friday, only when the answer depends on where the price ends up by Friday (What's the payoff on my Nike
  position? How does BABA look by Friday? How are my BABA calls doing? What does Friday look like across my book?): read
  payoff (legs "sold" when he asks how what he sold is doing; no ticker for the whole book). Then one "say" of two or
  three short sentences, written with every leg on, then {"payoff": true}: Sunny draws the card. Nothing else: no rows,
  no body, no trio. Never pick or suggest.
  One name: "By Friday, NKE flat adds {g:$180}. A drop to {b:34.16} costs {r:$4,270}, most of it the LEAPS. Tap a leg to
  take it out." Use the 1 SD price on the side that matters most, the leg that carries most of it (by_leg), a sold strike
  that caps or adds to it when one does. What he sold: what he keeps if the price is flat and where he keeps all of it
  (ends_by_then: under the call strike, over the put strike); when the sold legs end after Friday, say what is kept
  flat and where it starts to cost (breakevens). The book: "If every name moves the same % by Friday, flat adds
  {g:$1,640}, a 5% rise adds {g:$21,090} and a 5% drop costs {r:$31,650}. Tap a name for its own chart."
  Prices plain, as the card's axis shows them ({b:[r3|#2]}, never $). At most three sentences.
  Use the word in by_word for Friday. Adds is green, costs is red. When reports_before_then is there, say the report
  falls before then and IV is held. A name not in the book, or with nothing held, is text only.
  follow_ups such as "How are my NKE calls doing?", "And for BABA?", "What does Friday look like across my book?".
- The price chart, when he asks how a name is doing over time, or about a trend or an event on the chart (How's Nike
  doing this week / this month / this quarter / this year? Is Nike in an uptrend? Did Nike cross its 50-day? Show me
  Nike's 50-day chart): read chart with the range the question names (w when it names none; an uptrend is q), mark
  "cross" for a cross or a 50-day chart (range q). Then one "say" of ONE sentence and {"chart": true}: Sunny draws the
  card. Nothing else, and never a second sentence: one full stop. The sentence answers the question from the range asked: the move over it, then the one fact that
  matters most there. Week: "NKE is down {r:[r5|%]} this week at {b:[r1|$2]}, {b:[r9|%]} under your 36 calls with
  {g:[r12|%0]} captured." When worth_more_than_sold, say how far over the strike it sits instead. Month or quarter: where it sits against its 50-day. Year: against the 52-week high and low.
  A cross: "NKE crossed above its 50-day on Sep 30 and has stayed above since." When there is no cross this quarter,
  say it stayed above (or below) all quarter. Only the book's names have a chart; any other name is text only.
  follow_ups such as "NKE this quarter", "Did NKE cross its 50-day?".
- Your book, when he asks about all his positions at once (Show me all my positions. Which names are under their
  50-day? Show my positions as small charts): read book (range m for the 50-day, else the range named, w when none;
  view grid only when he asks for charts). Then one "say" of ONE sentence and {"book": true}: Sunny draws a row per
  name. The sentence names the one or two names that need him most, from the first rows: "NFLX is closest, {o:0.8%}
  under its 74 calls, then LULU {o:1.0%} under the Ceiling." For the 50-day: how many are under it and the furthest.
  This is not "all my sold positions" or "what I bought": those stay rows. follow_ups such as "Show them as small
  charts", "Which names are under their 50-day?".
- What if, when he asks what a move does to a name's delta, or whether its delta is safe (Is my BABA delta safe if it
  moves 10%? What does a 10% drop do to my Nike delta?): read delta_gamma with the ticker and move_pct (the move named,
  negative for a drop, 10 when none). Then one "say" of two short sentences and {"whatif": true}: Sunny draws the card
  with a slider and the hedge. Nothing else, and nothing about the hedge (the card tells it). First sentence, from at:
  "If BABA rises 10%, its delta falls to {o:206}, {o:19%} of long: thin." (the state in its tone: {o:} thin, {g:} on
  target). When at.state is Short, the net is below zero: "If LULU rises 10%, its delta turns short by {r:235}." and
  never "falls to" that figure. Second: "Slide to try any move up to 15%." A question without the
  word delta or safe that asks what a move does goes to the payoff. Only the book's names; the whole book stays rows.
  follow_ups such as "What does a 10% drop do to my BABA delta?", "And for NKE?".
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
- recap: one short line for his history list, slots allowed, no {b:} marks. It repeats the answer's own figures with
  the answer's own words: a figure that is below in the answer is never above in the recap. With a big number: the few words that go
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

/* A spoken question (28 Oct 2026, Nik: the phone's listening struggles with accents): the phone's words, which
   Claude reads for what he most likely meant. */
const SPOKEN = `This question was spoken and turned into text by the phone, so words may be misheard: a ticker said as
its company name or its sounds (Nike or "any key" for NKE, Ali Baba or "baba" for BABA, Lulu for LULU, "F I S" for FIS),
or a term (LEAPS as "leaps" or "leeps", Ceiling as "sealing"). Read it for what he most likely meant from his book.
When you read a word as something other than what was heard, begin the say with how you read it, in a few words:
"Reading that as NKE."`;

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

/** The roll's month panels and the shares panel (Nik, 28 Oct 2026), written here from the roll card so every
    month reads the same: each wall's strike, label and confidence, how many calls cover the delta needed and what
    they cost, and one call's delta at the low and price. Facts only: no pick, nothing marked best. */
const DOTS = (n: number | null) => (n == null ? '' : ' ' + '●'.repeat(Math.max(0, Math.min(3, n))) + '○'.repeat(3 - Math.max(0, Math.min(3, n))));
const monDay = (iso: string) => { const d = new Date(String(iso).slice(0, 10) + 'T12:00:00Z');
  return `${d.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' })} ${d.getUTCDate()}`; };
const cap = (x: string) => x.charAt(0).toUpperCase() + x.slice(1);
const listAnd = (xs: string[]) => (xs.length < 2 ? xs[0] ?? '' : xs.slice(0, -1).join(', ') + ' and ' + xs.at(-1));
function rollPanels(card: Row, src: Row | null): Row[] {
  const d = card.data ?? {}, need = Number(d.delta_needed ?? 0), out: Row[] = [];
  for (const m of (d.months ?? []) as Row[]) {
    const held = (m.hedge_calls_held_here ?? []) as Row[];
    out.push({ type: 'panel', title: `${monDay(m.expiry)} · ${m.days_left} days`,
      say: held.length ? `You hold ${listAnd(held.map((h) => `${fmt(h.contracts, '#')} at $${fmt(h.strike, 'k')}`))}.` : null,
      trio: null, table: null, note: null, source: null,
      rows: ((m.walls ?? []) as Row[]).map((w) => ({
        a: `$${fmt(w.strike, 'k')}`, a_tone: 'call',
        b: m.open_interest_only || !w.label ? ' Wall · open interest' : ` ${cap(String(w.label))}${DOTS(w.confidence)}`, b_tone: null,
        r: need > 0 ? `${fmt(w.calls_to_cover, '#')} calls · ${fmt(w.cost_usd, '$')}` : `${fmt(w.delta_per_call_at_low, '#')} a call`, r_tone: null,
        sub: `${fmt(w.delta_per_call_at_low, '#')} delta a call at the low · ${fmt(w.call_price, '$2')} each`, bar: null })) });
  }
  const sh = d.shares ?? {};
  out.push({ type: 'panel', title: 'Shares', say: null, trio: null, table: null, note: null, source: src,
    rows: [{ a: need > 0 ? `${fmt(sh.to_cover, '#')} shares` : 'No shares needed', a_tone: null, b: null, b_tone: null,
      r: need > 0 ? fmt(sh.cost_usd, '$') : null, r_tone: null, sub: 'Each share adds one delta at every price.', bar: null }] });
  return out;
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
    // A slot around a small plain number ("[1|#]") is not a slot: the number stands on its own.
    return sl.fill(t, bad).replace(/\[(\d[\d.,]*)(?:\|[^\]]*)?\]/g, '$1').replace(/ {2,}/g, ' ');
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
      /* The big number is drawn plain, its colour from tone: a colour mark around it ("{r:[r5|$]}") becomes the
         tone, never text on screen (28 Oct 2026: "{r:$60,223}" showed on the phone). */
      const raw = String(p.big.value ?? '').trim(), mk = raw.match(/^\{([gbro]):([\s\S]*)\}$/);
      const inner = mk ? mk[2] : raw, markTone = mk ? ({ g: 'up', r: 'down', o: 'thin', b: null } as Record<string, string | null>)[mk[1]] : null;
      const m = inner.match(/^\s*\[([^\]|]+)(?:\|([^\]]*))?\]\s*$/);
      let n: number | null = null, value: string | null = null, f2 = '';
      if (m) { try { n = Math.abs(sl.value(m[1])); f2 = (m[2] ?? '').trim(); value = fmt(n, f2); } catch (e) { bad.push(`${p.big.value}: ${(e as Error).message}`); } }
      else { const v = S(inner); value = v == null ? null : plain(v); }
      parts.push({ type: 'big', label: S(p.big.label), value, n, count: n != null && COUNTS.has(f2), fmt: f2, sub: S(p.big.sub), tone: tone(p.big.tone) ?? markTone });
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
    else if (p.roll_months) {
      const card = ran.filter((x) => x.ok && x.name === 'roll').at(-1)?.card;
      if (card) parts.push(...rollPanels(card, sourceLine('sunny', ran, c, seen, 0)));
    } else if (p.payoff) {
      // The payoff card (block 28): drawn on the phone from the lookup's own figures; its source line is its own.
      const card = ran.filter((x) => x.ok && x.name === 'payoff').at(-1)?.card;
      if (card?.chart) parts.push({ type: 'payoff', ...card.chart, at: marketOpen() ? clock(new Date(c.at)) : `${lastClose()} close` });
    } else if (p.chart) {
      // The price chart (block 29): every range at once, drawn on the phone; its source line is its own.
      const card = ran.filter((x) => x.ok && x.name === 'chart').at(-1)?.card;
      if (card?.chart) parts.push({ type: 'chart', ...card.chart, at: marketOpen() ? clock(new Date()) : `${lastClose()} close`, live: marketOpen() });
    } else if (p.book) {
      // Your book (block 29): a row per name, drawn on the phone; its source line is its own.
      const card = ran.filter((x) => x.ok && x.name === 'book').at(-1)?.card;
      if (card?.chart) parts.push({ type: 'book', ...card.chart, at: marketOpen() ? clock(new Date()) : `${lastClose()} close` });
    } else if (p.whatif) {
      // What if · Delta and Gamma (block 29): the slider's every step, drawn on the phone; its source line is its own.
      const card = ran.filter((x) => x.ok && x.name === 'delta_gamma' && x.card?.chart).at(-1)?.card;
      if (card?.chart && c.draws?.includes('whatif')) parts.push({ type: 'whatif', ...card.chart, at: marketOpen() ? clock(new Date(c.at)) : `${lastClose()} close` });
    }
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
  const source = last?.type === 'panel' || last?.type === 'none' || last?.type === 'payoff' || last?.type === 'chart' || last?.type === 'book' || last?.type === 'whatif' ? null : sourceLine(f.source ?? 'sunny', ran, c, seen, webN);
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
    case 'roll': return s(`Working out ${t}'s roll`);
    case 'payoff': return s(t ? `Working out ${t} by Friday` : 'Working out the book by Friday');
    case 'chart': return s(`Drawing ${t}'s chart`);
    case 'book': return s('Drawing your book');
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

async function ask(question: string, thread: Row[], deep: boolean, c: Ctx, owner: boolean, test: Test = {}, emit: Emit = () => {}, spoken = false) {
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
      `${deep ? DEEP + '\n\n' : ''}${spoken ? SPOKEN + '\n\n' : ''}Question: ${question}` },
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
        // The payoff's chart is the phone's (every leg, to redraw the card), never the model's.
        return { type: 'tool_result', tool_use_id: b.id, content: JSON.stringify({ ...card, chart: undefined, data: sl.tag(card.data) }) };
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
async function logAsk(book: string, user: string | undefined, q: string, threadLen: number, deep: boolean, a: Row, rid?: string): Promise<number | null> {
  const r = await rest('search_log?select=id', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify([{
    book_id: book, user_id: user ?? null, question: q, thread_len: threadLen, deep, model: a.model, effort: a.effort,
    // The phone's request id and what it is sent: an answer lost on the way is fetched again by the id (29 Oct 2026).
    rid: rid ?? null, reply: { parts: a.parts, source: a.source, follow_ups: a.follow_ups, recap: a.recap, can_answer: a.can_answer },
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
    'Which hedges roll soon?', 'What earnings are coming up?', 'How is payback going?', 'What does Friday look like across my book?',
    'Show me all my positions', 'Which names are under their 50-day?', 'Show my positions as small charts',
    ...names.flatMap((t) => [`How’s ${t}?`, `${t}’s walls this week`, `Give me an update on ${t}`, `What’s my sold position on ${t}?`,
      `What did ${t}’s bought legs cost?`, `How much time value is left on ${t}?`, `Why did ${t} move today?`, `Who is trading ${t}?`,
      `What’s the payoff on my ${t} position?`, `How are my ${t} calls doing?`, `How’s ${t} doing this week?`,
      `How’s ${t} doing this quarter?`, `Is ${t} in an uptrend?`, `Did ${t} cross its 50-day?`,
      `Is my ${t} delta safe if it moves 10%?`, `What does a 10% drop do to my ${t} delta?`]),
  ];
  return { questions: all, tries: [`Give me an update on ${first}`, 'What’s the value of my calls sold?', 'What do I need to do today?', 'What’s my delta right now?'] };
}

/** Suggestions in place of Recent (Nik, 28 Oct 2026): up to six questions picked from the book each time Search
    opens, each with the reason it is there. To do first; then rolls for the names most short of delta by Thursday;
    names reporting in the next two weeks; the newest saved research; then what changed and the delta. */
async function suggest(c: Ctx, owner: boolean): Promise<Row[]> {
  const out: Row[] = [], seen = new Set<string>();
  const add = (q: string, why: string, t?: string) => { if (out.length < 6 && !out.some((x) => x.q === q)) { out.push({ q, why }); if (t) seen.add(t); } };
  const todo = (await lookup('todo', {}, c, owner).catch(() => null))?.data?.to_do ?? 0;
  add('What do I need to do today?', todo ? `${todo} order${todo === 1 ? '' : 's'} in To do` : 'Nothing left in To do');
  const plan = (c.p.plan ?? {}) as Record<string, Row>;
  const short = Object.entries(plan).map(([t, p]) => ({ t, s: p.story })).filter((x) => x.s && !x.s.earnings && x.s.need > 0)
    .sort((a, b) => b.s.need - a.s.need).slice(0, 2);
  for (const { t, s } of short) add(`I want to roll my ${t} calls`, `About ${fmt(Math.round(s.need / 10) * 10, '#')} delta short by Thursday`, t);
  const soon = ((c.p.writes?.names ?? []) as Row[]).filter((n) => n.next_earnings?.date && n.next_earnings.date >= c.today)
    .map((n) => ({ t: String(n.ticker), d: String(n.next_earnings.date) }))
    .filter((x) => (Date.parse(x.d) - Date.parse(c.today)) / 864e5 <= 14).sort((a, b) => a.d.localeCompare(b.d));
  const reacted = new Set((await db('research_numbers?topic=eq.earnings_reactions&checked_at=not.is.null&select=ticker').catch(() => [])).map((r) => String(r.ticker)));
  const day = (iso: string) => new Date(iso + 'T12:00:00Z').toLocaleString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
  for (const { t, d } of soon.slice(0, 2)) {
    add(reacted.has(t) ? `How did ${t} move after its last earnings?` : `Give me an update on ${t}`, `${t} reports ${day(d)}`, t);
  }
  const fresh = await db('research_numbers?topic=eq.fair_value&metric=eq.fair_value_average&checked_at=not.is.null&select=ticker,asof,source&order=asof.desc,created_at.desc&limit=20').catch(() => []);
  const mine = fresh.filter((x) => plan[String(x.ticker)]);   // research on this book's names only
  const r = mine.find((x) => !seen.has(String(x.ticker))) ?? mine[0];
  if (r) add(`What’s ${r.ticker}’s fair value?`, `${r.source} report from ${day(String(r.asof))}`, String(r.ticker));
  add('What changed today?', 'Since the first read this morning');
  add('What’s my delta right now?', 'Across the book, in shares');
  return out;
}

/** Words the phone's listening should expect (its contextual strings): the book's and watchlist's tickers, the
    names said for them, and the book's own terms. */
const SAID: Record<string, string[]> = { BABA: ['Alibaba'], FIS: ['Fidelity National'], LULU: ['Lululemon'], NFLX: ['Netflix'],
  NKE: ['Nike'], PEP: ['PepsiCo', 'Pepsi'], UBER: ['Uber'], TSLA: ['Tesla'], APP: ['AppLovin'], INTU: ['Intuit'], ADBE: ['Adobe'],
  PYPL: ['PayPal'], VZ: ['Verizon'], TMUS: ['T-Mobile'], SPCX: ['SpaceX'] };
function hints(c: Ctx): string[] {
  const tickers = [...Object.keys(c.p.plan ?? {}), ...((c.p.watchlist ?? []) as Row[]).map((w) => String(w.ticker)), 'SPY', 'QQQ', 'IWM'];
  return [...new Set([...tickers, ...tickers.flatMap((t) => SAID[t] ?? []), 'LEAPS', 'delta', 'gamma', 'theta', 'Ceiling', 'Floor',
    'Accelerator', 'flip', 'walls', 'To do', 'hedge calls', 'insurance puts', 'roll', 'strike', 'premium', 'time value', 'fair value',
    'Investing Pro', 'earnings', 'expiry', 'standard deviation'])];
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
    if (Array.isArray(body.draws)) c.draws = body.draws.map(String).slice(0, 20);
    if (body.questions) return json({ ok: true, build: BUILD, ...questions(c) });
    if (typeof body.answer_for === 'string') {
      const rid = encodeURIComponent(body.answer_for.slice(0, 64));
      const who2 = who.user ? `user_id=eq.${who.user}` : 'user_id=is.null';
      const r = await rest(`search_log?rid=eq.${rid}&book_id=eq.${book}&${who2}&select=id,reply&limit=1`);
      const row = r.ok ? ((await r.json()) as Row[])[0] : null;
      if (!row?.reply) return json({ ok: true, pending: true });
      if (body.client_error) await rest(`search_log?id=eq.${row.id}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ client_error: String(body.client_error).slice(0, 500) }) }).then((x) => x.body?.cancel());
      return json({ ok: true, answer: { ...row.reply, id: row.id } });
    }
    if (body.suggest) return json({ ok: true, build: BUILD, suggestions: await suggest(c, who.owner), hints: hints(c) });
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
        const a = await ask(q, thread, !!body.deep, c, who.owner, who.system ? body.test ?? {} : {}, emit, !!body.voice);
        const rid = typeof body.rid === 'string' ? body.rid.slice(0, 64) : undefined;
        const id = body.test ? null : await logAsk(book, who.user, q, thread.length, !!body.deep, a, rid);
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
