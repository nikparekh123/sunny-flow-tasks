// The web's shared state (README "State"): which account is open, privacy, the rail view, the Time value sheet and the
// Activity panel.
// Picking an account changes every card about a book; market cards stay the same.
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useBooks, type BookId } from './data';
import { maskMoney } from './format';

export type Account = BookId;
/** The Home rail: What you hold or By name (handoff 2026-11-18, SunnyRail pills), remembered per computer; opens on
    What you hold. */
export type RailView = 'hold' | 'name';

const read = (k: string) => { try { return localStorage.getItem(k); } catch { return null; } };
const write = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* private window */ } };

interface WebState {
  /** The book open now: S, N or T (Together). */
  book: BookId | null;
  /** Every book this login holds, menu order: Sunny, Nicolay, Together. */
  books: BookId[];
  account: Account;
  pickAccount: (a: Account) => void;
  privacy: boolean;
  setPrivacy: (on: boolean) => void;
  /** Hides book dollars when privacy is on (prices with two decimals stay). */
  mask: (s: string) => string;
  railView: RailView;
  setRailView: (v: RailView) => void;
  tvOpen: boolean;
  setTvOpen: (on: boolean) => void;
  /** The Activity panel (handoff 2026-11-18, 161a): open or not, and the line to show when a Levels row opened it
      (`n` counts each open, so the same line asked twice scrolls to it again). */
  actOpen: boolean;
  actFocus: { key: string; n: number } | null;
  openActivity: (key?: string) => void;
  closeActivity: () => void;
}

const Ctx = createContext<WebState | null>(null);

export function WebStateProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const onOverview = useLocation().pathname.startsWith('/overview');
  const { data: members } = useBooks();
  const books = useMemo<BookId[]>(() => {
    const ids = (members ?? []).map((m) => m.book_id);
    return (['S', 'N', 'T'] as BookId[]).filter((b) => ids.includes(b));
  }, [members]);

  /* ⚠ TOGETHER FIRST (Nik, 24 Nov 2026: "the default view for me will always be Together"): a new visit opens on
     Together when the login holds it; a pick lasts for the tab (sessionStorage), so a reload keeps it but the next
     visit opens on Together again. A login without Together opens on S when held, else its first book. */
  const [account, setAccount] = useState<Account | null>(() => { try { return sessionStorage.getItem('sw-acct') as Account | null; } catch { return null; } });
  const pick = (a: Account | null): Account | null => (!books.length ? null : a && books.includes(a) ? a
    : books.includes('T') ? 'T' : books.includes('S') ? 'S' : books[0]);
  const book: BookId | null = pick(account);
  useEffect(() => { if (onOverview) navigate('/home', { replace: true }); }, [onOverview, navigate]);

  const pickAccount = useCallback((a: Account) => {
    setAccount(a);
    try { sessionStorage.setItem('sw-acct', a); } catch { /* private window */ }
  }, []);

  const [privacy, setPrivacyS] = useState(() => read('sw-privacy') === '1');
  const setPrivacy = useCallback((on: boolean) => { setPrivacyS(on); write('sw-privacy', on ? '1' : '0'); }, []);
  const [railView, setRailViewS] = useState<RailView>(() => (read('sw-rail-by') === 'name' ? 'name' : 'hold'));
  const setRailView = useCallback((v: RailView) => { setRailViewS(v); write('sw-rail-by', v); }, []);
  const [tvOpen, setTvOpen] = useState(false);
  const [actOpen, setActOpen] = useState(false);
  const [actFocus, setActFocus] = useState<{ key: string; n: number } | null>(null);
  const openActivity = useCallback((key?: string) => {
    setActOpen(true);
    setActFocus((f) => (key ? { key, n: (f?.n ?? 0) + 1 } : null));
  }, []);
  const closeActivity = useCallback(() => setActOpen(false), []);

  const mask = useCallback((s: string) => (privacy ? maskMoney(s) : s), [privacy]);

  const value = useMemo(() => ({ book, books, account: book ?? 'S', pickAccount, privacy, setPrivacy, mask, railView, setRailView, tvOpen, setTvOpen,
    actOpen, actFocus, openActivity, closeActivity }),
  [book, books, pickAccount, privacy, setPrivacy, mask, railView, setRailView, tvOpen, actOpen, actFocus, openActivity, closeActivity]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useWeb(): WebState {
  const v = useContext(Ctx);
  if (!v) throw new Error('useWeb outside WebStateProvider');
  return v;
}
