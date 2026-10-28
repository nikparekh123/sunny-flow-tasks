/**
 * Sunny search test page · sunnyfi.co/ask (step 3, Nik 27 Oct 2026). A plain page for judging the search's answers
 * while Claude Design draws the real screens: type or speak a question, see the short answer, the big number, each
 * card's data as plain tables, and follow-ups. Answers in one session form a thread ("and for BABA?" carries on);
 * "Go deeper" asks the same question again with more thinking. No link anywhere; type the URL.
 * Self-gated like /payoff. Local dev: ?fixture answers every question from public/dev/ask-sample.json, without auth.
 */
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Auth from '@/pages/Auth';
import { supabase } from '@/integrations/supabase/client';
import './ask.css';

const DEV_FIXTURE = import.meta.env.DEV && new URLSearchParams(window.location.search).has('fixture');

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
interface Card { type: string; tag: string; source: { kind: string; at?: string; day?: string; note?: string; asof?: string }; data: Json }
interface Answer {
  ok: boolean; error?: string; route: string; model: string; answer: string; big: { value: string; label: string } | null;
  cards: Card[]; follow_ups: string[]; can_answer: boolean; ms: number;
  usage: { input: number; output: number; cache_read: number; cache_write: number };
  lookups: { name: string; args: Record<string, Json>; ok: boolean; ms: number; error?: string }[];
}
interface Turn { q: string; deep: boolean; a?: Answer; err?: string }

/** Dollars per million tokens: input, output (cache reads 0.1x input, cache writes 1.25x input). */
const PRICE: Record<string, [number, number]> = { 'claude-haiku-5-5': [0.1, 0.5], 'claude-opus-5-5': [4, 20] };
function cost(a: Answer): string {
  const p = PRICE[a.model];
  if (!p) return '';
  const u = a.usage;
  const usd = (u.input * p[0] + u.cache_read * p[0] * 0.1 + u.cache_write * p[0] * 1.25 + u.output * p[1]) / 1e6;
  return usd < 0.01 ? 'under 1 cent' : `about ${(usd * 100).toFixed(1)} cents`;
}
const modelName = (m: string) => (m.includes('haiku') ? 'Haiku' : m.includes('opus') ? 'Opus' : m);

async function askServer(q: string, thread: { q: string; a: string }[], deep: boolean): Promise<Answer> {
  if (DEV_FIXTURE) {
    const a = (await (await fetch('/dev/ask-sample.json')).json()) as Answer;
    return { ...a, answer: `(sample) ${a.answer}` };
  }
  const { data, error } = await supabase.functions.invoke('sunny-search', { body: { ask: q, thread, deep } });
  if (error) throw error;
  if (!data?.ok) throw new Error(data?.error ?? 'the search did not answer');
  return data as Answer;
}

/* ── Card data as plain tables ───────────────────────────────────────────────────────────────────────── */

function cell(v: Json): string {
  if (v == null) return '–';
  if (typeof v === 'number') return Number.isInteger(v) ? v.toLocaleString('en-US') : v.toLocaleString('en-US', { maximumFractionDigits: 2 });
  if (typeof v === 'boolean') return v ? 'yes' : 'no';
  if (typeof v === 'string') return v;
  if (Array.isArray(v) && v.every((x) => x == null || typeof x !== 'object')) return v.map(cell).join(', ');
  return JSON.stringify(v);
}
const isRows = (v: Json): v is { [k: string]: Json }[] =>
  Array.isArray(v) && v.length > 0 && v.every((x) => x != null && typeof x === 'object' && !Array.isArray(x));

function DataView({ v, depth = 0 }: { v: Json; depth?: number }): ReactNode {
  if (isRows(v)) {
    const cols = [...new Set(v.flatMap((r) => Object.keys(r)))].slice(0, 12);
    return (
      <div className="ak-scroll">
        <table className="ak-table">
          <thead><tr>{cols.map((c) => <th key={c}>{c.replace(/_/g, ' ')}</th>)}</tr></thead>
          <tbody>{v.slice(0, 60).map((r, i) => <tr key={i}>{cols.map((c) => <td key={c}>{cell(r[c] ?? null)}</td>)}</tr>)}</tbody>
        </table>
      </div>
    );
  }
  if (v != null && typeof v === 'object' && !Array.isArray(v) && depth < 3) {
    return (
      <dl className="ak-dl">
        {Object.entries(v).map(([k, x]) => (
          <div key={k} className={x != null && typeof x === 'object' && !(Array.isArray(x) && !isRows(x)) ? 'ak-row ak-row-wide' : 'ak-row'}>
            <dt>{k.replace(/_/g, ' ')}</dt>
            <dd><DataView v={x} depth={depth + 1} /></dd>
          </div>
        ))}
      </dl>
    );
  }
  return <span>{cell(v)}</span>;
}

function source(c: Card): string {
  const s = c.source ?? { kind: '' };
  const at = s.at ? new Date(s.at).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'America/New_York' }) : '';
  if (s.kind === 'live') return `Live${s.note ? ` · ${s.note}` : ''}${at ? ` · ${at}` : ''}`;
  return `Sunny${s.day ? ` · ${s.day}` : ''}${at ? ` · updated ${at}` : ''}`;
}

function CardBox({ c }: { c: Card }) {
  const [raw, setRaw] = useState(false);
  return (
    <section className="ak-card">
      <header>
        <span className="ak-tag">{c.tag}</span>
        <button type="button" className="ak-link" onClick={() => setRaw(!raw)}>{raw ? 'Table' : 'Raw'}</button>
      </header>
      <div className="ak-source">{source(c)}</div>
      {raw ? <pre className="ak-raw">{JSON.stringify(c.data, null, 2)}</pre> : <DataView v={c.data} />}
    </section>
  );
}

/* ── The page ────────────────────────────────────────────────────────────────────────────────────────── */

export default function AskPage() {
  const auth = useAuth();
  const user = DEV_FIXTURE ? ({ id: 'dev' } as typeof auth.user) : auth.user;
  const loading = DEV_FIXTURE ? false : auth.loading;
  const [q, setQ] = useState('');
  const [turns, setTurns] = useState<Turn[]>([]);
  const [busy, setBusy] = useState(false);
  const [listening, setListening] = useState(false);
  const rec = useRef<{ stop: () => void } | null>(null);
  const end = useRef<HTMLDivElement>(null);

  useEffect(() => { end.current?.scrollIntoView({ behavior: 'smooth', block: 'end' }); }, [turns.length, busy]);

  async function ask(question: string, deep = false) {
    const text = question.trim();
    if (!text || busy) return;
    setQ('');
    setBusy(true);
    const thread = turns.filter((t) => t.a?.ok).map((t) => ({ q: t.q, a: t.a!.answer })).slice(-6);
    setTurns((ts) => [...ts, { q: text, deep }]);
    try {
      const a = await askServer(text, thread, deep);
      setTurns((ts) => ts.map((t, i) => (i === ts.length - 1 ? { ...t, a } : t)));
    } catch (e) {
      setTurns((ts) => ts.map((t, i) => (i === ts.length - 1 ? { ...t, err: (e as Error).message } : t)));
    } finally {
      setBusy(false);
    }
  }

  /* Voice: the browser's own speech recognition where it has one (Safari and Chrome); the keyboard's mic works too. */
  type Rec = { lang: string; interimResults: boolean; onresult: (e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void;
    onend: () => void; onerror: () => void; start: () => void; stop: () => void };
  const SR = (window as unknown as Record<string, (new () => Rec) | undefined>).SpeechRecognition
    ?? (window as unknown as Record<string, (new () => Rec) | undefined>).webkitSpeechRecognition;
  function listen() {
    if (!SR) return;
    if (listening) { rec.current?.stop(); return; }
    const r = new SR();
    r.lang = 'en-US';
    r.interimResults = true;
    let heard = '';
    r.onresult = (e) => {
      heard = Array.from(e.results).map((x) => x[0].transcript).join('');
      setQ(heard);
    };
    r.onend = () => { setListening(false); rec.current = null; if (heard.trim()) void ask(heard); };
    r.onerror = () => { setListening(false); rec.current = null; };
    rec.current = r;
    setListening(true);
    r.start();
  }

  if (loading) return <div className="ak"><p className="ak-muted">Signing in…</p></div>;
  if (!user) return <Auth />;

  return (
    <div className="ak">
      <div className="ak-head">
        <h1>Sunny search</h1>
        <span className="ak-muted">Test page · answers form one thread</span>
        {turns.length > 0 && <button type="button" className="ak-link" onClick={() => setTurns([])}>New thread</button>}
      </div>

      {turns.length === 0 && (
        <div className="ak-suggest">
          {['What do I need to do today?', 'How much time value is left in what I sold?', "What's BABA's gamma?",
            'Which calls are 80% captured?', 'What happens to the book if the market falls 5%?', 'How did October go?'].map((s) => (
            <button key={s} type="button" className="ak-chip" onClick={() => void ask(s)}>{s}</button>
          ))}
        </div>
      )}

      {turns.map((t, i) => (
        <article key={i} className="ak-turn">
          <div className="ak-q">{t.q}{t.deep && <span className="ak-deep">Go deeper</span>}</div>
          {!t.a && !t.err && <p className="ak-muted">Working it out…</p>}
          {t.err && <p className="ak-err">{t.err}</p>}
          {t.a && (
            <>
              <div className="ak-meta">
                {modelName(t.a.model)}{t.a.route === 'deeper' ? ' · deeper' : ''} · {(t.a.ms / 1000).toFixed(1)} s · {cost(t.a)}
                {!t.a.can_answer && ' · could not answer'}
              </div>
              {t.a.big && (
                <div className="ak-big">
                  <div className="ak-big-v">{t.a.big.value}</div>
                  <div className="ak-big-l">{t.a.big.label}</div>
                </div>
              )}
              <p className="ak-answer">{t.a.answer}</p>
              {t.a.cards.map((c, j) => <CardBox key={j} c={c} />)}
              <div className="ak-follow">
                {t.a.follow_ups.map((f) => <button key={f} type="button" className="ak-chip" disabled={busy} onClick={() => void ask(f)}>{f}</button>)}
                {t.a.route !== 'deeper' && i === turns.length - 1 && (
                  <button type="button" className="ak-chip ak-chip-deep" disabled={busy} onClick={() => void ask(t.q, true)}>Go deeper</button>
                )}
              </div>
              <details className="ak-details">
                <summary>What it read ({t.a.lookups.length})</summary>
                <ul>
                  {t.a.lookups.map((l, j) => (
                    <li key={j}>{l.name}{l.args.ticker ? ` · ${String(l.args.ticker)}` : ''}{Object.keys(l.args).filter((k) => k !== 'ticker').length
                      ? ` · ${JSON.stringify(Object.fromEntries(Object.entries(l.args).filter(([k]) => k !== 'ticker')))}` : ''} · {l.ms} ms{l.ok ? '' : ` · failed: ${l.error}`}</li>
                  ))}
                </ul>
              </details>
            </>
          )}
        </article>
      ))}
      <div ref={end} />

      <form className="ak-bar" onSubmit={(e) => { e.preventDefault(); void ask(q); }}>
        <input
          id="ak-q" value={q} onChange={(e) => setQ(e.target.value)} placeholder={listening ? 'Listening…' : 'Ask about your book'}
          autoComplete="off" enterKeyHint="search" disabled={busy}
        />
        {SR && (
          <button type="button" className={listening ? 'ak-mic ak-mic-on' : 'ak-mic'} onClick={listen} disabled={busy}
            aria-label={listening ? 'Stop listening' : 'Speak your question'}>
            <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M12 15a3 3 0 0 0 3-3V6a3 3 0 1 0-6 0v6a3 3 0 0 0 3 3Zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-2.08A7 7 0 0 0 19 12h-2Z" /></svg>
          </button>
        )}
        <button type="submit" className="ak-go" disabled={busy || !q.trim()}>{busy ? '…' : 'Ask'}</button>
      </form>
    </div>
  );
}
