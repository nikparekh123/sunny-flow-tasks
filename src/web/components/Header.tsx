// The fixed header on every page (README "Global chrome · Header").
import { useLocation, useNavigate } from 'react-router-dom';
import { headerTime, useNY } from '../lib/clock';
import { useWeb } from '../lib/state';

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
        <button type="button" className="bare" onClick={() => nav('/home')} style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-.03em' }}>Sunny</button>
        <nav style={{ alignSelf: 'stretch', display: 'flex', gap: 28 }}>
          {tabs.map((t) => (
            <button key={t.k} type="button" className="bare sw-navtab" onClick={t.go} aria-current={t.on ? 'page' : undefined}
              style={{ display: 'flex', alignItems: 'center', fontSize: 15, fontWeight: t.on ? 700 : 400, color: t.on ? '#F5F5F7' : '#98989D',
                boxShadow: `inset 0 -2px 0 ${t.on ? '#F5F5F7' : 'transparent'}` }}>{t.l}</button>
          ))}
        </nav>
        <span style={{ flex: 1 }} />
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
      <style>{`.sw .sw-navtab:hover{color:#F5F5F7!important}.sw .sw-pv:hover{filter:brightness(1.3)}`}</style>
    </header>
  );
}
