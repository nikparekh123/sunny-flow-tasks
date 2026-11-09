// The account menu on Home and Overview (README "Account menu"): Sunny, Nicolay, Both accounts, then Sign out.
// Each row's value is that book's account value from its own Home snapshot.
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { signOut } from '../lib/auth';
import { useHome, type BookId } from '../lib/data';
import { dollars } from '../lib/format';
import { useWeb, type Account } from '../lib/state';

export const BOOK_NAME: Record<BookId, string> = { S: 'Sunny', N: 'Nicolay' };
export const accountTitle = (a: Account) => (a === 'both' ? 'Both accounts' : BOOK_NAME[a]);

export function AccountMenu() {
  const { account, books, pickAccount, mask } = useWeb();
  const nav = useNavigate();
  const [open, setOpen] = useState(false);
  const s = useHome(books.includes('S') ? 'S' : null).data?.payload?.account?.value as number | undefined;
  const n = useHome(books.includes('N') ? 'N' : null).data?.payload?.account?.value as number | undefined;

  useEffect(() => {
    if (!open) return;
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', esc);
    return () => window.removeEventListener('keydown', esc);
  }, [open]);

  const rows: { k: Account; mono: string; l: string; v: string }[] = [];
  if (books.includes('S')) rows.push({ k: 'S', mono: 'S', l: 'Sunny', v: s != null ? `${dollars(s)} total balance` : '' });
  if (books.includes('N')) rows.push({ k: 'N', mono: 'N', l: 'Nicolay', v: n != null ? `${dollars(n)} total balance` : '' });
  if (books.length > 1) rows.push({ k: 'both', mono: 'S N', l: 'Both accounts', v: s != null && n != null ? `${dollars(s + n)} together` : '' });

  return (
    <div style={{ position: 'relative' }}>
      <button type="button" className="bare sw-am" onClick={() => setOpen((o) => !o)} aria-haspopup="menu" aria-expanded={open}
        style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 30, lineHeight: '36px', fontWeight: 600, letterSpacing: '-.02em' }}>
        {accountTitle(account)}
        <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" style={{ marginTop: 3 }}>
          <path d="M3.5 6l4.5 4.5L12.5 6" style={{ fill: 'none', stroke: '#F5F5F7', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' }} />
        </svg>
      </button>
      {open && (
        <>
          <button type="button" aria-label="Close" className="bare" onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 40, cursor: 'default' }} />
          <div role="menu" className="g2" style={{ position: 'absolute', left: -6, top: 46, zIndex: 41, width: 340, borderRadius: 16, overflow: 'hidden' }}>
            <div style={{ padding: '16px 20px', fontSize: 17, fontWeight: 600, borderBottom: '1px solid rgba(255,255,255,.14)' }}>Select an account</div>
            {rows.map((a) => (
              <button key={a.k} type="button" role="menuitemradio" aria-checked={account === a.k} className="bare sw-amrow"
                onClick={() => { setOpen(false); pickAccount(a.k); }}
                style={{ width: '100%', display: 'grid', fontVariantNumeric: 'tabular-nums', gridTemplateColumns: '36px minmax(0,1fr) 20px', gap: 14,
                  alignItems: 'center', padding: '14px 20px', borderTop: '1px solid rgba(255,255,255,.08)' }}>
                <span style={{ width: 36, height: 36, borderRadius: '50%', background: 'rgba(255,255,255,.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700 }}>{a.mono}</span>
                <span style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
                  <span style={{ fontSize: 15, fontWeight: 500 }}>{a.l}</span>
                  <span style={{ fontSize: 13, color: '#98989D' }}>{mask(a.v)}</span>
                </span>
                {account === a.k ? (
                  <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M3.5 9.5l3.5 3.5 7.5-8" style={{ fill: 'none', stroke: '#65C466', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }} /></svg>
                ) : <span />}
              </button>
            ))}
            <button type="button" className="bare sw-amrow" onClick={async () => { setOpen(false); await signOut(); nav('/', { replace: true }); }}
              style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 14, padding: '13px 20px', borderTop: '1px solid rgba(255,255,255,.14)', fontSize: 14, color: '#FF6961' }}>
              Sign out
            </button>
          </div>
        </>
      )}
      <style>{`.sw .sw-am:hover{opacity:.85}.sw .sw-amrow:hover{background:rgba(255,255,255,.05)}`}</style>
    </div>
  );
}
