// The ⓘ next to "Sundial" (Nik, 27 Nov 2026: "a page on how it works so I can reference it, shown as an i next to
// Sundial"). The page itself is public/sundial/how.html, one file for the web and the app, so an edit there reaches
// both without a TestFlight build. Here: the round i, and a panel from the right (full screen when narrow) with the
// page in it; the scrim, ✕ or Escape closes it. The web is dark only, so the page is asked for dark.
import { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';

const INK = '#F2F2F2';
export const HOW_URL = '/sundial/how.html';

export function SundialInfo({ size = 24 }: { size?: number }) {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return;
    const k = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', k);
    const o = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { window.removeEventListener('keydown', k); document.body.style.overflow = o; };
  }, [open]);
  const narrow = typeof window !== 'undefined' && window.innerWidth < 700;
  return (
    <>
      <button type="button" className="bare" aria-label="How Sundial works" title="How Sundial works"
        onClick={(e) => { e.stopPropagation(); setOpen(true); }}
        style={{ flex: 'none', width: size, height: size, borderRadius: '50%', boxShadow: 'inset 0 0 0 1.5px rgba(250,250,250,.42)',
          color: INK, fontSize: Math.round(size * 0.58), lineHeight: `${size}px`, fontWeight: 500, fontStyle: 'italic', fontFamily: 'Georgia, serif',
          textAlign: 'center', cursor: 'pointer', padding: 0, alignSelf: 'center' }}>
        i
      </button>
      {open && createPortal(
        <div role="dialog" aria-modal="true" aria-label="How Sundial works"
          style={{ position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', justifyContent: 'flex-end' }}>
          <div onClick={() => setOpen(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.55)' }} />
          <div style={{ position: 'relative', width: narrow ? '100%' : 640, height: '100%', background: '#171717',
            boxShadow: narrow ? 'none' : '-1px 0 0 rgba(250,250,250,.08)', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '12px 12px 0' }}>
              <button type="button" className="bare" aria-label="Close" onClick={() => setOpen(false)}
                style={{ width: 36, height: 36, borderRadius: 18, background: '#2A2A2A', color: INK, fontSize: 18, lineHeight: '36px', cursor: 'pointer', padding: 0 }}>
                ✕
              </button>
            </div>
            <iframe title="How Sundial works" src={`${HOW_URL}?theme=dark`} style={{ flex: 1, width: '100%', border: 0, background: '#171717' }} />
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
