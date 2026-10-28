/**
 * The number check (Sunny search, step 5, 27 Oct 2026; Nik's rule 9: "a check rejects text whose numbers don't
 * match"). Every figure in an answer must be in the data that answer read, or follow from it by one step of plain
 * arithmetic (a sum, a difference, a product, a ratio or a percent), rounded the way the answer shows it. A figure
 * worked out from another checked figure counts too ($184,785 left, then 31 weeks at $5,894 a week). Dates, years
 * and small counts (up to 20: "3 days", "6 names") are not checked.
 */
type Json = null | boolean | number | string | Json[] | { [k: string]: Json };

const MONTHS = '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*';

/** Every number in the data, as absolute values (signs are worded in answers: "lose $17,441"). */
export function dataNumbers(v: Json, out: Set<number> = new Set()): Set<number> {
  if (v == null || typeof v === 'boolean') return out;
  if (typeof v === 'number') { if (Number.isFinite(v)) out.add(Math.abs(v)); return out; }
  if (typeof v === 'string') {
    for (const m of v.matchAll(/-?\d[\d,]*\.?\d*/g)) { const n = Number(m[0].replace(/,/g, '')); if (Number.isFinite(n)) out.add(Math.abs(n)); }
    return out;
  }
  if (Array.isArray(v)) { for (const x of v) dataNumbers(x, out); return out; }
  for (const x of Object.values(v)) dataNumbers(x, out);
  return out;
}

export interface Figure { text: string; value: number; tol: number }

/** The figures an answer states, each with the rounding its own digits allow. */
export function figures(text: string): Figure[] {
  let t = text.replace(/\b\d{4}-\d{2}-\d{2}\b/g, ' ');
  t = t.replace(new RegExp(`\\b\\d{1,2}\\s+${MONTHS}\\b`, 'g'), ' ');
  t = t.replace(new RegExp(`${MONTHS}\\s+\\d{1,2}(,\\s*\\d{4})?\\b`, 'g'), ' ');
  t = t.replace(/\b(19|20)\d{2}\b/g, ' ');
  const out: Figure[] = [];
  for (const m of t.matchAll(/(\$)?(-)?(\d[\d,]*\.?\d*)\s*(K|k|M)?(%)?/g)) {
    const raw = m[3].replace(/\.$/, '').replace(/,/g, '');
    if (!raw) continue;
    const dec = raw.includes('.') ? raw.split('.')[1].length : 0;
    const mult = m[4] === 'K' || m[4] === 'k' ? 1000 : m[4] === 'M' ? 1e6 : 1;
    const value = Number(raw) * mult;
    if (!Number.isFinite(value)) continue;
    out.push({ text: m[0].trim().replace(/\.$/, ''), value, tol: Math.max(0.51 * 10 ** -dec * mult, 0.006 * value) });
  }
  return out;
}

/** Whether a value can be reached from the pool in one step of arithmetic. */
function derivable(target: number, tol: number, pool: number[]): boolean {
  const near = (x: number) => Math.abs(x - target) <= tol;
  for (let i = 0; i < pool.length; i++) {
    const a = pool[i];
    for (let j = 0; j < pool.length; j++) {
      const b = pool[j];
      if (near(a + b) || near(Math.abs(a - b)) || near(a * b)) return true;
      if (b !== 0 && (near(a / b) || near((a / b) * 100) || near(Math.abs(a / b - 1) * 100))) return true;
    }
  }
  return false;
}

export interface CheckResult { ok: boolean; checked: number; unverified: string[] }

/** Check an answer's figures against everything it read, and the question itself ("if the market falls 5%"). */
export function checkAnswer(text: string, read: Json[], question = ''): CheckResult {
  const set = new Set<number>();
  for (const r of read) dataNumbers(r, set);
  for (const f of figures(question)) set.add(f.value);
  // Keep the pool to a size the pair search can run through quickly.
  let pool = [...set].filter((x) => x !== 0).sort((a, b) => a - b);
  if (pool.length > 1500) pool = pool.filter((x, i) => i % Math.ceil(pool.length / 1500) === 0 || x >= 1);
  const unverified: string[] = [];
  let checked = 0;
  const pending: Figure[] = [];
  for (const f of figures(text)) {
    if (Number.isInteger(f.value) && f.value <= 20 && !f.text.includes('$') && !f.text.includes('%')) continue;
    checked++;
    if (pool.some((p) => Math.abs(p - f.value) <= f.tol)) { pool.push(f.value); continue; }
    pending.push(f);
  }
  // Worked-out figures: one step from the data, or from a figure already checked; twice, so chains settle.
  for (let pass = 0; pass < 2 && pending.length; pass++) {
    for (let i = pending.length - 1; i >= 0; i--) {
      if (derivable(pending[i].value, pending[i].tol, pool)) { pool.push(pending[i].value); pending.splice(i, 1); }
    }
  }
  for (const f of pending) unverified.push(f.text);
  return { ok: unverified.length === 0, checked, unverified };
}
