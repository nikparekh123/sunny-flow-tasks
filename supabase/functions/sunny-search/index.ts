/**
 * sunny-search · Sunny search (Nik, 27 Oct 2026; brief: https://claude.ai/artifact/9SbMGjPUaMpw1hvo4gSjo6).
 *   POST { list: true }                     ->  the card menu (19 lookups with their arguments)
 *   POST { lookup, args? }                  ->  { card }: one lookup on its own (step 1)
 *   POST { ask, thread?, deep? }            ->  { id, answer, big, cards, follow_ups, can_answer, check, cost_usd }
 *   POST { feedback: { id, value } }       ->  thumbs on an answer: up, down or not_asked (step 5)
 * Step 5: every figure in an answer is checked against the data it read (check.ts); one that fails gets one retry, then
 * the words are withheld and only the cards show. Every question is logged (search_log; the weekly misses are the view
 * search_misses), and a book's search spend is capped per day (SEARCH_DAILY_USD, default $5).
 * Asking: Claude Opus 5.5 answers every question at low effort; "Go deeper" (deep: true) asks again at medium effort.
 * (27 Oct 2026, step 4: Opus alone was as fast as Haiku sorting and answering, with better answers at about 2.8 cents
 * a question; Nik chose it.) It reads only through the lookups, so every number comes from Sunny's data, and writes
 * one or two plain lines, an optional big number and the cards to show. It never writes and never trades.
 * Who may call: the scheduler's x-cron-key, the service-role key, or a signed-in member of a book (only that book).
 */
import Anthropic from 'npm:@anthropic-ai/sdk@1.3.0';
import { caller, context, lookup, MENU, SB_KEY, SB_URL, type Ctx, type Row } from './lookups.ts';
import { checkAnswer } from './check.ts';

const BUILD = '2026-10-27.13';
const MODEL = 'claude-opus-5-5';
/** Test runs may still try Haiku on its own (step 4). */
const HAIKU = 'claude-haiku-5-5';
const MAX_STEPS = 6;
const client = new Anthropic();

// ── The tools: the card menu, as Claude sees it ──────────────────────────────────────────────────────────

const TOOLS = MENU.map((m) => ({
  name: m.name,
  description: m.shows,
  input_schema: { type: 'object', properties: m.args ?? {}, required: m.required ?? [], additionalProperties: false },
}));
const CARD_NAMES = MENU.map((m) => m.name as string);

/** What Claude hands back at the end: the answer, an optional big number, the cards to show, follow-ups. */
const ANSWER_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['answer', 'big', 'cards', 'follow_ups', 'can_answer'],
  properties: {
    answer: { type: 'string', description: 'One or two short, plain sentences. Every number in it comes from a lookup.' },
    big: {
      anyOf: [{ type: 'null' }, {
        type: 'object', additionalProperties: false, required: ['value', 'label'],
        properties: { value: { type: 'string', description: 'The one figure, formatted, e.g. $3,804' },
                      label: { type: 'string', description: 'What it is, e.g. Time value left in what you sold' } } }],
    },
    cards: {
      type: 'array', description: 'The cards to show, most useful first, each a lookup you ran',
      items: { type: 'object', additionalProperties: false, required: ['lookup', 'ticker'],
               properties: { lookup: { type: 'string', enum: CARD_NAMES }, ticker: { anyOf: [{ type: 'string' }, { type: 'null' }] } } },
    },
    follow_ups: { type: 'array', items: { type: 'string' }, description: 'Two or three short next questions' },
    can_answer: { type: 'boolean', description: "false when Sunny's data cannot answer the question" },
  },
};

const SYSTEM = `You are the search in Sunny, Nik's options app. Nik runs an income book: deep in-the-money LEAPS calls on a
few names, a weekly call sold against each LEAPS at the money, hedge calls bought to stay delta positive up to +1.5 SD by
Thursday's close, insurance puts, and weekly puts sold only when the gates pass. Answer his question from his own data.

How to answer:
- Always read with the lookups first, then answer. Never answer from memory, and never say you need to look something
  up: look it up. Use the lookups for every figure; never state a number, strike, date or count you did not read.
- Answer in one or two short, plain sentences. Lead with the answer. No jargon he did not use, no em dashes, no hedging.
- Quote dates, expiries and strikes exactly as the data gives them, year included (the LEAPS expire in 2028, the
  hedges in 2027: never mix them up). Write dates the way people say them: 30 Oct, or 21 Jan 2028 when the year
  is not this one; never 2028-01-21.
- Use the same figure, rounded the same way, in "big" and in the answer.
- For walls, read gamma first: it has the tape's labels (Ceiling, Floor, Accelerator). Use walls_live only when gamma
  has no view for that ticker or expiry, and never give both sets of walls in one answer.
- "big" is only for a question that asks for exactly one figure (how much, how many, what is X's price or delta).
  For anything else, including a name's gamma, walls or position, big is null.
- Choose the cards that show the answer: usually one to three, at most five when he asks several things at once.
  Every card must be a lookup you ran, with the same ticker (null when you ran it for all names).
- Name the period of any realized, interest or fee figure (since 31 Aug, this month), since Home shows them by range.
- If his data cannot answer it, say "I can't answer that from your data", set can_answer to false, and suggest the
  nearest questions that do work.
- Suggest two or three short follow-up questions he would plausibly ask next.
- Research (fundamentals, analyst_targets, earnings_history, research_notes) is what Nik saved from sources such as
  Investing Pro. Name the source and date when you use it ("Investing Pro, 27 Oct"). It is context only: never let
  it change To do, strikes or hedges. If nothing is saved for a name, say so plainly.
- You only read. You never place, change or cancel a trade; To do and its buttons are his.

When you have read what you need, reply with only a JSON object, no other text:
{"answer": "one or two sentences", "big": {"value": "$3,804", "label": "Time value left in what you sold"} or null,
 "cards": [{"lookup": "<a lookup you ran>", "ticker": "BABA" or null}], "follow_ups": ["...", "..."], "can_answer": true}

Terms: captured % is how much of a sold option's premium is already earned. Walls are option strikes where dealers'
gamma piles up: a Ceiling or Floor tends to hold, an Accelerator speeds a move through it, Unclear has no clear read.
The flip is the price where dealer gamma turns from calming to amplifying. Net after hedges is premium sold, less what
was paid to close options, less this week's share of hedge costs. Insurance puts are long puts; hedge calls are long
calls that are not LEAPS.`;

// ── Asking ───────────────────────────────────────────────────────────────────────────────────────────────

const answerText = (f: Row) => String(f.answer ?? '') + (f.big?.value ? ` ${f.big.value}` : '');
const readData = (ran: Ran[]) => ran.filter((x) => x.ok && x.card).map((x) => x.card!.data);

/** The answer object from the model's last text: plain JSON, or JSON inside a code fence. */
function parseAnswer(text: string): Row | null {
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) return null;
  try { const o = JSON.parse(m[0]); return typeof o.answer === 'string' ? o : null; } catch { return null; }
}

interface Ran { name: string; args: Row; ok: boolean; ms: number; card?: Row; error?: string }

/** Test runs only (step 4): force one model and effort for every question, and return everything each answer read. */
interface Test { model?: 'haiku' | 'opus'; effort?: 'low' | 'medium' | 'high'; trace?: boolean }

async function ask(question: string, thread: Row[], deep: boolean, c: Ctx, owner: boolean, test: Test = {}) {
  const t0 = Date.now();
  const kind = deep ? 'deeper' : 'quick';
  const model = test.model === 'haiku' ? HAIKU : MODEL;
  const effort = test.effort ?? (deep ? 'medium' : 'low');
  const ran: Ran[] = [];
  const usage = { input: 0, output: 0, cache_read: 0, cache_write: 0 };
  const names = Object.keys(c.p.plan ?? {}).sort().join(', ');
  const messages: Row[] = [
    // Earlier questions in this thread, as plain text: "and for BABA?" carries on from them.
    ...thread.flatMap((x) => [{ role: 'user', content: String(x.q ?? '') }, { role: 'assistant', content: String(x.a ?? '') }]),
    { role: 'user', content: `Today is ${c.today}. Names in the book: ${names}. Watchlist: ${
      (c.p.watchlist ?? []).map((w: Row) => w.ticker).join(', ') || 'none'}.\n\nQuestion: ${question}` },
  ];
  let final: Row | null = null, stop = '', retried = false, firstMiss: string[] = [];
  for (let step = 0; step < MAX_STEPS; step++) {
    const req: Row = {
      model, max_tokens: 16000, system: SYSTEM, tools: TOOLS, messages,
      cache_control: { type: 'ephemeral' },
      // No answer format while it reads: with one, Haiku answered before looking anything up (27 Oct 2026).
      output_config: { effort },
    };
    // Opus answers with Anthropic's server-side fallback on, so a declined answer is retried on another model.
    const r: Row = model === MODEL
      ? await client.beta.messages.create({ ...req, betas: ['server-side-fallback-2026-07-01'], fallbacks: 'default' } as any)
      : await client.messages.create(req as any);
    usage.input += r.usage?.input_tokens ?? 0; usage.output += r.usage?.output_tokens ?? 0;
    usage.cache_read += r.usage?.cache_read_input_tokens ?? 0; usage.cache_write += r.usage?.cache_creation_input_tokens ?? 0;
    stop = String(r.stop_reason);
    if (stop === 'refusal' || stop === 'max_tokens') break;
    messages.push({ role: 'assistant', content: r.content });
    if (stop === 'pause_turn') continue;
    const calls = (r.content as Row[]).filter((b) => b.type === 'tool_use');
    if (!calls.length) {
      final = parseAnswer((r.content as Row[]).filter((b) => b.type === 'text').map((b) => b.text).join(''));
      // THE NUMBER CHECK (rule 9): a figure not in the data it read, and not worked out from it, gets one retry.
      if (final && !retried) {
        const ck = checkAnswer(answerText(final), readData(ran), question);
        if (!ck.ok) {
          retried = true; firstMiss = ck.unverified;
          messages.push({ role: 'user', content: `These figures are not in the data you read and cannot be worked out from it: ${
            ck.unverified.join(', ')}. Answer again using only figures from the lookups (read more if you need to), in the same JSON.` });
          final = null;
          continue;
        }
      }
      break;
    }
    // All of this turn's lookups at once, their results back in one message.
    const results = await Promise.all(calls.map(async (b) => {
      const s = Date.now(), args = (b.input ?? {}) as Row;
      try {
        const card = await lookup(String(b.name), args, c, owner);
        ran.push({ name: b.name, args, ok: true, ms: Date.now() - s, card });
        return { type: 'tool_result', tool_use_id: b.id, content: JSON.stringify(card) };
      } catch (e) {
        const error = (e as Error).message;
        ran.push({ name: b.name, args, ok: false, ms: Date.now() - s, error });
        return { type: 'tool_result', tool_use_id: b.id, content: error, is_error: true };
      }
    }));
    messages.push({ role: 'user', content: results });
  }

  // Not valid JSON at the end: one more short call puts what it wrote into the answer format.
  if (!final && (stop === 'end_turn' || stop === 'tool_use')) {
    try {
      const r: Row = await client.messages.create({ model, max_tokens: 4000, system: SYSTEM,
        messages: [...messages, { role: 'user', content: 'Give your final answer now, in the answer format.' }],
        output_config: { effort: 'low', format: { type: 'json_schema', schema: ANSWER_SCHEMA } } } as any);
      usage.input += r.usage?.input_tokens ?? 0; usage.output += r.usage?.output_tokens ?? 0;
      final = parseAnswer((r.content as Row[]).filter((b) => b.type === 'text').map((b) => b.text).join(''));
    } catch { /* falls through to "can't answer" */ }
  }

  // The cards: each one Claude chose, from the lookups it ran (the same name and ticker), in its order.
  const up = (x: unknown) => (x ? String(x).toUpperCase() : null);
  const cards: Row[] = [];
  const okRan = ran.filter((x) => x.ok && x.card);
  for (const want of (final?.cards ?? []) as Row[]) {
    // Same lookup and ticker; failing that, the same lookup however it was run (a list read for one name).
    const hit = okRan.find((x) => x.name === want.lookup && up(x.args.ticker) === up(want.ticker) && !cards.includes(x.card!))
      ?? okRan.find((x) => x.name === want.lookup && !cards.includes(x.card!));
    if (hit?.card) cards.push(hit.card);
  }
  // No card named, but it read something: show what it read (at most three), so an answer is never bare.
  if (!cards.length) for (const x of okRan.slice(0, 3)) if (!cards.includes(x.card!)) cards.push(x.card!);
  const answered = !!final && stop !== 'refusal';
  // Still a figure it cannot back after the retry: the words are withheld, the cards (plain data) still show.
  const check = answered ? checkAnswer(answerText(final!), readData(ran), question) : { ok: true, checked: 0, unverified: [] as string[] };
  const withheld = answered && !check.ok;
  return {
    ok: true, build: BUILD, route: kind, model,
    answer: !answered ? "I can't answer that from your data."
      : withheld ? "I couldn't check every figure in that answer against your data, so I've left it out. Here is what I read." : final!.answer,
    big: answered && !withheld ? final!.big ?? null : null,
    check: { ok: check.ok, checked: check.checked, unverified: check.unverified, retried, first_try_unverified: firstMiss },
    cards,
    follow_ups: answered ? (final!.follow_ups ?? []).slice(0, 3) : [],
    can_answer: answered && !withheld ? final!.can_answer !== false : false,
    lookups: ran.map(({ card: _c, ...x }) => x),
    ...(test.trace ? { read: ran.map((x) => ({ name: x.name, args: x.args, data: x.card?.data ?? null })) } : {}),
    usage, stop, effort, ms: Date.now() - t0,
  };
}

// ── The log, the cost and the daily guard (step 5) ──────────────────────────────────────────────────────

/** Dollars per million tokens, input and output (cache reads 0.1x input, cache writes 1.25x input). */
const PRICE: Record<string, [number, number]> = { 'claude-opus-5-5': [4, 20], 'claude-haiku-5-5': [0.1, 0.5] };
const costOf = (model: string, u: Row) => {
  const p = PRICE[model] ?? PRICE[MODEL];
  return (u.input * p[0] + u.cache_read * p[0] * 0.1 + u.cache_write * p[0] * 1.25 + u.output * p[1]) / 1e6;
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
async function logAsk(book: string, user: string | undefined, q: string, threadLen: number, deep: boolean, a: Row): Promise<number | null> {
  const r = await rest('search_log?select=id', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify([{
    book_id: book, user_id: user ?? null, question: q, thread_len: threadLen, deep, model: a.model, effort: a.effort,
    answer: a.answer, big: a.big, cards: (a.cards as Row[]).map((x) => x.type), lookups: a.lookups,
    can_answer: a.can_answer, check_ok: a.check?.ok ?? null, unverified: a.check?.unverified ?? [], retried: a.check?.retried ?? false,
    ms: a.ms, tokens: a.usage, cost_usd: Number(costOf(a.model, a.usage).toFixed(5)) }]) });
  if (!r.ok) { await r.body?.cancel(); return null; }
  return Number(((await r.json()) as Row[])[0]?.id ?? null);
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
    const c = await context(book);
    if (body.lookup) return json({ ok: true, build: BUILD, card: await lookup(String(body.lookup), body.args ?? {}, c, who.owner) });
    if (body.ask) {
      const q = String(body.ask).trim().slice(0, 1000);
      if (!q) return json({ ok: false, error: 'empty question' }, 400);
      const spent = await spentToday(book);
      if (spent >= DAILY_USD) return json({ ok: true, build: BUILD, answer: `Today's search limit ($${DAILY_USD}) is reached. It resets at midnight.`,
        big: null, cards: [], follow_ups: [], can_answer: false, limit: { daily_usd: DAILY_USD, spent_usd: Number(spent.toFixed(2)) } });
      const thread = Array.isArray(body.thread) ? body.thread.slice(-6) : [];
      // Test settings only for the scheduler and service keys (the step 4 runs), never from the app.
      const a = await ask(q, thread, !!body.deep, c, who.owner, who.system ? body.test ?? {} : {});
      const id = body.test ? null : await logAsk(book, who.user, q, thread.length, !!body.deep, a);
      return json({ ...a, id, cost_usd: Number(costOf(a.model, a.usage).toFixed(4)) });
    }
    // Thumbs on an answer: up, down, or "not what I asked"; only on the caller's own book.
    if (body.feedback) {
      const f = body.feedback as Row, value = String(f.value ?? '');
      if (!['up', 'down', 'not_asked'].includes(value) || !Number.isFinite(Number(f.id))) return json({ ok: false, error: 'bad feedback' }, 400);
      const r = await rest(`search_log?id=eq.${Number(f.id)}&book_id=eq.${book}`, { method: 'PATCH', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ feedback: value, feedback_at: new Date().toISOString() }) });
      await r.body?.cancel();
      return json({ ok: r.ok, build: BUILD });
    }
    return json({ ok: false, error: 'send { ask }, { lookup }, or { list: true }' }, 400);
  } catch (e) {
    return json({ ok: false, build: BUILD, error: (e as Error).message }, 400);
  }
});
