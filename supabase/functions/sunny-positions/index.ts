/**
 * sunny-positions: one name of a book on the Positions grid (handoff 6 Nov 2026, block 31, Pass 2).
 *
 * Nik, 6 Nov 2026: the maths runs on the server and the phone only adds the numbers up and draws them. So
 * when Positions opens a name, the phone asks for it here and gets every leg's P&L, delta, theta and vega
 * at 101 prices (today's price ±12%) for each date-slider stop, plus the OTM call a fix would buy. Turning a
 * leg off, dragging the price and the fixes' previews are then sums of these numbers on the phone.
 *
 * POST { book: 'S' | 'N', t: 'NKE' } with the signed-in user's JWT (verify_jwt = true).
 * ⚠ READ AS THE CALLER: the book's home_snapshot is fetched with the caller's own token, so RLS decides who
 * sees what (members of the book only). Nothing here uses the service key.
 *
 * Inputs come from sunny-home's last build (payload.brief_inputs: legs in days from that build, each
 * option's IV, the 4% rate, dividends). The clock is moved on by the time since that build before pricing.
 * The engine is the one Home uses (_shared/book-engine.ts), so the turns-short price matches Home's.
 */
import { type Div, type Leg, NameBook, positionsGrid, type Stop } from '../_shared/book-engine.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const json = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });

type NameInput = { t: string; S0: number; P0: number; iv: number; legs: Leg[]; divs: Div[]; stops: Stop[]; fridayStop: number;
  otm: { K: number; ex: string; days: number; label: string } | null };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json(401, { error: 'sign in' });
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const book = String(body.book ?? 'S').toUpperCase(), t = String(body.t ?? '').toUpperCase();
  if (!/^[A-Z]$/.test(book) || !/^[A-Z.]{1,8}$/.test(t)) return json(400, { error: 'send book and t' });

  const r = await fetch(`${URL_}/rest/v1/home_snapshot?book_id=eq.${book}&select=built_at,inputs:payload->brief_inputs`,
    { headers: { apikey: ANON, Authorization: auth } });
  if (!r.ok) return json(r.status === 401 ? 401 : 502, { error: 'could not read the book' });
  const rows = await r.json() as { built_at: string; inputs: { built_at: string; r: number; names: NameInput[] } | null }[];
  const inp = rows[0]?.inputs;
  if (!inp) return json(404, { error: 'no positions for this book yet' });
  const n = inp.names.find((x) => x.t === t);
  if (!n) return json(404, { error: `${t} is not held in this book` });

  // Move the clock on from the build to now: every "days from now" shrinks by the time gone.
  const gone = Math.max(0, (Date.now() - Date.parse(inp.built_at)) / 864e5);
  const legs = n.legs.map((l) => (l.ty === 'S' ? l : { ...l, days: l.days - gone }));
  const divs = n.divs.map((d) => ({ ...d, days: d.days - gone }));
  const stops = n.stops.map((s) => ({ ...s, tt: s.tt === 0 ? 0 : Math.max(0, s.tt - gone) }));
  const otm = n.otm ? { ...n.otm, days: n.otm.days - gone } : null;
  const nb = new NameBook({ t, S0: n.S0, P0: n.P0, iv: n.iv, legs, divs, r: inp.r });
  const g = positionsGrid(nb, stops, otm);
  return json(200, { v: 1, book, ...g, fridayStop: n.fridayStop, built_at: inp.built_at, priced_at: new Date().toISOString() });
});
