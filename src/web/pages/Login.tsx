// Sign in (README 0, `Web Login.dc.html`, dark). The real sign-in is the 10-digit code (A1, Nik 8 Nov 2026):
// tried on Nik's login, then his cousin's, as on the phone.
import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import '../web.css';
import { getCurrentSession, signInWithCode } from '../lib/auth';
import { marketStatus, ny } from '../lib/clock';

const INK = '#F5F5F7', MU = '#AEAEB2', RED = '#FF6961';
const GL = 'linear-gradient(160deg,rgba(255,255,255,.10) 0%,rgba(255,255,255,.03) 38%,rgba(255,255,255,.02) 62%,rgba(255,255,255,.07) 100%)';

export default function Login() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [code, setCode] = useState('');
  const [foc, setFoc] = useState(false);
  const [bad, setBad] = useState(params.get('denied') === '1');
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(() => ny());
  const inRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    getCurrentSession().then((s) => { if (s?.user) navigate('/home', { replace: true }); });
    const t = setInterval(() => setNow(ny()), 15_000);
    const f = setTimeout(() => inRef.current?.focus(), 60);
    return () => { clearInterval(t); clearTimeout(f); };
  }, [navigate]);

  const mkt = marketStatus(now);
  const ready = code.length === 10 && !busy, on = ready || busy;
  const left = 10 - code.length;
  const msg = busy ? 'SIGNING IN…' : bad ? 'THAT CODE DIDN’T WORK. CHECK IT AND TRY AGAIN.'
    : !code.length ? 'ENTER THE 10-DIGIT ACCESS CODE.' : left ? `${left} MORE ${left === 1 ? 'DIGIT' : 'DIGITS'}.` : 'PRESS ENTER TO SIGN IN.';
  const hm = `${String(now.h).padStart(2, '0')}:${String(now.m).padStart(2, '0')}`;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (code.length !== 10 || busy) return;
    setBusy(true);
    const res = await signInWithCode(code);
    if (res.ok) { navigate('/home', { replace: true }); return; }
    setBusy(false);
    setBad(true);
  };

  return (
    <div className="sw" data-screen-label="Sign in" style={{ position: 'relative', minHeight: '100vh', display: 'grid', gridTemplateRows: 'auto 1fr auto',
      gap: 32, padding: '28px 48px 40px', overflow: 'hidden', color: INK }}>
      <div aria-hidden="true" style={{ position: 'absolute', inset: 0, pointerEvents: 'none', background:
        'radial-gradient(60vw 52vw at 4% -10%,rgba(101,196,102,.28),transparent 62%),radial-gradient(52vw 52vw at 104% 30%,rgba(115,182,249,.22),transparent 60%),radial-gradient(62vw 50vw at 30% 116%,rgba(247,206,70,.16),transparent 62%)' }} />
      <div style={{ position: 'relative', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 16, fontSize: 12, fontWeight: 600, letterSpacing: '.24em' }}>
        <span>SUNNY</span>
        <span style={{ fontVariantNumeric: 'tabular-nums', letterSpacing: '.14em', fontWeight: 500, color: MU }}>{hm} · NYC</span>
      </div>
      <h1 style={{ position: 'relative', alignSelf: 'center', margin: 0, maxWidth: 1400, fontSize: 'clamp(56px,9.4vw,184px)', lineHeight: 0.9,
        fontWeight: 800, letterSpacing: '-.05em', textWrap: 'balance' } as React.CSSProperties}>
        Welcome to Sunny Wealth Management<span style={{ color: '#65C466' }}>.</span>
      </h1>
      <div style={{ position: 'relative', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', gap: 32, flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, fontSize: 12, letterSpacing: '.06em', lineHeight: '18px', color: MU }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 8, fontWeight: 600, color: INK }}>
            <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#65C466', opacity: mkt.live ? 1 : 0.35, boxShadow: '0 0 10px rgba(101,196,102,.8)' }} />
            {mkt.line}
          </span>
          <span style={{ fontWeight: 500 }}>Private. For invited accounts only.</span>
        </div>
        <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 10, width: 'min(480px,100%)',
          padding: '18px 20px 14px', borderRadius: 24, background: GL, WebkitBackdropFilter: 'blur(14px) saturate(180%)', backdropFilter: 'blur(14px) saturate(180%)',
          boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.16),inset 1.5px 1.5px 0 -.5px rgba(255,255,255,.28),0 10px 24px -6px rgba(0,0,0,.4)' }}>
          <label htmlFor="code" style={{ alignSelf: 'stretch', fontSize: 11, fontWeight: 600, letterSpacing: '.24em', color: MU }}>SIGN IN</label>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12, width: '100%' }}>
            <div onClick={() => inRef.current?.focus()} style={{ position: 'relative', flex: 1, minWidth: 0, display: 'flex', alignItems: 'flex-end', height: 44, cursor: 'text' }}>
              {Array.from({ length: 10 }, (_, i) => {
                const cur = foc && i === Math.min(code.length, 9) && !busy, full = i < code.length;
                const bc = bad ? RED : cur ? INK : full ? 'rgba(245,245,247,.7)' : 'rgba(245,245,247,.28)';
                return (
                  <span key={i} style={{ flex: 1, marginLeft: i === 3 || i === 6 ? 14 : 0, marginRight: 3, height: 40, display: 'flex', alignItems: 'flex-end',
                    justifyContent: 'center', paddingBottom: 6, fontSize: 24, lineHeight: '24px', fontWeight: 600, fontVariantNumeric: 'tabular-nums',
                    boxShadow: `inset 0 ${cur || bad ? '-2.5px' : '-1.5px'} 0 ${bc}`, transition: 'box-shadow .15s' }}>{code[i] ?? ''}</span>
                );
              })}
              <input id="code" ref={inRef} value={code} inputMode="numeric" autoComplete="one-time-code" maxLength={10}
                aria-label="10-digit access code" aria-invalid={bad} aria-describedby="msg"
                onChange={(e) => { setCode((e.target.value || '').replace(/\D/g, '').slice(0, 10)); setBad(false); }}
                onFocus={() => setFoc(true)} onBlur={() => setFoc(false)}
                style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', opacity: 0, border: 'none', background: 'transparent', color: 'transparent', caretColor: 'transparent', fontSize: 24 }} />
            </div>
            <button type="submit" disabled={!ready} className="bare" style={{ flex: 'none', cursor: ready ? 'pointer' : 'default', height: 44, padding: '0 20px',
              display: 'flex', alignItems: 'center', gap: 8, borderRadius: 999, fontSize: 12, fontWeight: 700, letterSpacing: '.18em',
              background: on ? '#F5F5F7' : 'rgba(118,118,128,.24)', color: on ? '#000000' : 'rgba(245,245,247,.6)', transition: 'background .2s,color .2s' }}>
              {busy ? 'SIGNING IN' : 'SIGN IN'}<span aria-hidden="true" style={{ fontSize: 15, letterSpacing: 0 }}>↵</span>
            </button>
          </div>
          <span id="msg" role="status" style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.14em', textAlign: 'right', color: bad ? RED : MU }}>{msg}</span>
        </form>
      </div>
    </div>
  );
}
