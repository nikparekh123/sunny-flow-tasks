// The fixed header on every page (README "Global chrome · Header"; the top bar from handoff 2026-11-11, Explorations 138a).
//
// 138a (Nik, 11 Nov 2026): no wordmark; the Sunny sun rises out of the bar. The bar's bottom edge is the horizon (the
// mark has no line of its own) and the edge warms under the sun. The design's bar is 48 tall; the built one stays 64,
// so the spec's relations are kept on it: the mark's flat edge sits on the bar's bottom edge, the tabs 9 from it.
import { useState, type CSSProperties } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { headerTime, useNY } from '../lib/clock';
import { useWeb } from '../lib/state';
import { TodoButton } from '../todo/TodoPopover';

const EASE = 'cubic-bezier(.22,1,.36,1)';
// The app icon's five rays, inner end to outer end, so each draws outward. o: 0 to 4 left to right; the middle (2) first.
const RAYS: [number, number, number, number, number][] = [
  [2, 50, 33, 50, 25], [1, 35.5, 36.89, 31.5, 29.96], [3, 64.5, 36.89, 68.5, 29.96], [0, 24.89, 47.5, 17.96, 43.5], [4, 75.11, 47.5, 82.04, 43.5],
];

/** The sun mark (56 x 31, flat edge on the bar's bottom edge) and the edge glow under it, with the load motion. */
function Sun() {
  // Reduce Motion: no motion, the final frame (web.css also turns every animation off under it).
  const [rm] = useState(() => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches);
  const A = (v: string) => (rm ? 'none' : v);
  const glow: CSSProperties = {
    position: 'absolute', left: -38, bottom: 0, width: 220, height: 1, transformOrigin: '66px 0', pointerEvents: 'none',
    background: 'linear-gradient(90deg, rgba(242,169,59,0) 0%, #F2A93B 24%, #F2A93B 36%, rgba(242,169,59,0) 100%)',
    boxShadow: '0 0 10px rgba(242,169,59,.55)',
    animation: A(`s138glow 1.3s ${EASE} .2s both, s138breathe 6s ease-in-out 1.8s infinite`),
  };
  return (
    <>
      <span aria-hidden="true" style={glow} />
      <svg aria-hidden="true" width={56} height={31} viewBox="14 22 72 40" style={{ flex: 'none', display: 'block' }}>
        <defs>
          <linearGradient id="swSunTop" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFE98F" /><stop offset="1" stopColor="#F7CE46" /></linearGradient>
          {/* The horizon: the disc rises from under the bar's edge and is clipped there. */}
          <clipPath id="swSunTopClip"><rect x="0" y="0" width="100" height="62" /></clipPath>
        </defs>
        <g clipPath="url(#swSunTopClip)">
          <path d="M28,62 A22,22 0 0 1 72,62 Z" fill="url(#swSunTop)" style={{ animation: A(`s138rise 1.1s ${EASE} both`) }} />
        </g>
        <g style={{ stroke: '#F7CE46', strokeWidth: 4.5, strokeLinecap: 'round' }}>
          {RAYS.map(([o, x1, y1, x2, y2]) => (
            // 0.70 s the middle, 0.79 s the inner pair, 0.88 s the outer pair, each 0.45 s.
            <line key={o} x1={x1} y1={y1} x2={x2} y2={y2}
              style={{ strokeDasharray: 8.5, animation: A(`s138ray .45s ${EASE} ${0.7 + [2, 1, 0, 1, 2][o] * 0.09}s both`) }} />
          ))}
        </g>
      </svg>
    </>
  );
}

export function Header() {
  const nav = useNavigate();
  const loc = useLocation();
  const n = useNY(15_000);
  const { privacy, setPrivacy } = useWeb();
  // The ticker page keeps the tab it came from selected (state.from: 'home' | 'positions').
  const from = (loc.state as { from?: string } | null)?.from;
  const onPositions = loc.pathname.startsWith('/positions') || (loc.pathname.startsWith('/t/') && from === 'positions');
  const tabs = [
    // Overview (Both accounts) selects neither tab, as the design draws it.
    { k: 'home', l: 'Home', on: !onPositions && !loc.pathname.startsWith('/overview'), go: () => nav('/home') },
    { k: 'positions', l: 'Positions', on: onPositions, go: () => nav('/positions') },
  ];
  const pvL = privacy ? 'Show amounts' : 'Hide amounts';
  return (
    <header className="glass-header" style={{ position: 'fixed', top: 0, left: 0, right: 0, zIndex: 10, height: 64 }}>
      <div style={{ maxWidth: 1440, height: '100%', margin: '0 auto', padding: '0 48px', display: 'flex', alignItems: 'center', gap: 36 }}>
        {/* The sun and the tabs, 32 apart as in the design (the bar's other gaps stay as built). */}
        <div style={{ alignSelf: 'stretch', display: 'flex', gap: 32 }}>
          <button type="button" className="bare" onClick={() => nav('/home')} aria-label="Sunny, Home"
            style={{ position: 'relative', alignSelf: 'stretch', display: 'flex', alignItems: 'flex-end' }}>
            <Sun />
          </button>
          <nav style={{ alignSelf: 'stretch', display: 'flex', gap: 32 }}>
            {tabs.map((t) => (
              <button key={t.k} type="button" className="bare sw-navtab" onClick={t.go} aria-current={t.on ? 'page' : undefined}
                style={{ display: 'flex', alignItems: 'flex-end', paddingBottom: 9, fontSize: 14, lineHeight: '20px', fontWeight: 400,
                  color: t.on ? '#F5F5F7' : '#98989D', boxShadow: `inset 0 -1px 0 ${t.on ? '#F5F5F7' : 'transparent'}` }}>{t.l}</button>
            ))}
          </nav>
        </div>
        <span style={{ flex: 1 }} />
        <TodoButton />
        <button type="button" className="bare sw-pv" onClick={() => setPrivacy(!privacy)} aria-pressed={privacy} aria-label={pvL} title={pvL}
          style={{ flex: 'none', width: 36, height: 36, borderRadius: '50%', background: privacy ? 'rgba(255,255,255,.2)' : 'rgba(118,118,128,.2)',
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" style={{ fill: 'none', stroke: '#F5F5F7', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
            <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" />
            {privacy && <path d="M4 4l16 16" />}
          </svg>
        </button>
        <span style={{ fontSize: 12, letterSpacing: '.04em', color: '#98989D', whiteSpace: 'nowrap' }}>{headerTime(n)}</span>
      </div>
      <style>{`.sw .sw-navtab:hover{color:#F5F5F7!important}.sw .sw-pv:hover{filter:brightness(1.3)}
@keyframes s138rise{from{transform:translateY(22px)}to{transform:translateY(0)}}
@keyframes s138ray{from{opacity:0;stroke-dashoffset:8}to{opacity:1;stroke-dashoffset:0}}
@keyframes s138glow{from{opacity:0;transform:scaleX(.3)}to{opacity:1;transform:scaleX(1)}}
@keyframes s138breathe{0%,100%{opacity:1}50%{opacity:.65}}`}</style>
    </header>
  );
}
