// Counts a formatted number up (the design's CountUp): 900 ms the first time, 600 ms on a change, ease-out cubic,
// from the last value when the suffix matches. Reduced motion shows the final value at once.
import { useLayoutEffect, useRef } from 'react';

const parse = (s: string) => {
  const m = /^(.*?)(\d[\d,]*(?:\.\d+)?)(.*)$/.exec(s || '');
  if (!m) return null;
  const raw = m[2];
  return { pre: m[1], n: parseFloat(raw.replace(/,/g, '')), dec: raw.includes('.') ? raw.split('.')[1].length : 0, com: raw.includes(','), suf: m[3] };
};

export function CountUp({ v, className, style }: { v: string; className?: string; style?: React.CSSProperties }) {
  const ref = useRef<HTMLSpanElement>(null);
  const prev = useRef<string | null>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const to = parse(v), fr = prev.current != null ? parse(prev.current) : null, first = prev.current == null;
    prev.current = v;
    if (!to || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) { el.textContent = v; return; }
    const n0 = fr && fr.suf === to.suf ? fr.n : 0, D = first ? 900 : 600, t0 = performance.now();
    const f = (x: number) => to.pre + (to.com ? x.toLocaleString('en-US', { minimumFractionDigits: to.dec, maximumFractionDigits: to.dec }) : x.toFixed(to.dec)) + to.suf;
    let id = 0;
    const step = (now: number) => {
      const k = Math.min(1, Math.max(0, (now - t0) / D)), e = 1 - Math.pow(1 - k, 3);
      el.textContent = k < 1 ? f(n0 + (to.n - n0) * e) : v;
      if (k < 1) id = requestAnimationFrame(step);
    };
    el.textContent = f(n0);
    id = requestAnimationFrame(step);
    return () => cancelAnimationFrame(id);
  }, [v]);
  return <span ref={ref} className={className} style={{ fontVariantNumeric: 'tabular-nums', ...style }} />;
}
