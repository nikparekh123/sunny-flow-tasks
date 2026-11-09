// The web's shared state (README "State"): which account is open, privacy, the rail view and the Time value sheet.
// Picking an account changes every card about a book; market cards stay the same.
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useBooks, type BookId } from './data';
import { maskMoney } from './format';

export type Account = BookId | 'both';
export type RailView = 'rails' | 'tiles';

const read = (k: string) => { try { return localStorage.getItem(k); } catch { return null; } };
const write = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* private window */ } };

interface WebState {
  /** The book open now: S or N. On Overview it is the book the page came from. */
  book: BookId | null;
  /** Every book this login holds, S first. */
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
}

const Ctx = createContext<WebState | null>(null);

export function WebStateProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const onOverview = useLocation().pathname.startsWith('/overview');
  const { data: members } = useBooks();
  const books = useMemo<BookId[]>(() => {
    const ids = (members ?? []).map((m) => m.book_id);
    return (['S', 'N'] as BookId[]).filter((b) => ids.includes(b));
  }, [members]);

  const [account, setAccount] = useState<Account>(() => (read('sw-acct') as Account) || 'S');
  const [lastBook, setLastBook] = useState<BookId>(() => ((read('sw-acct') === 'N') ? 'N' : 'S'));
  // A login that does not hold the remembered book opens on S when held, else its first book.
  useEffect(() => {
    if (!books.length) return;
    if (account === 'both' && books.length < 2) setAccount(books[0]);
    else if (account !== 'both' && !books.includes(account)) setAccount(books.includes('S') ? 'S' : books[0]);
  }, [books, account]);

  const pickAccount = useCallback((a: Account) => {
    setAccount(a);
    write('sw-acct', a);
    if (a !== 'both') setLastBook(a);
    navigate(a === 'both' ? '/overview' : '/home');
  }, [navigate]);

  const [privacy, setPrivacyS] = useState(() => read('sw-privacy') === '1');
  const setPrivacy = useCallback((on: boolean) => { setPrivacyS(on); write('sw-privacy', on ? '1' : '0'); }, []);
  const [railView, setRailViewS] = useState<RailView>(() => (read('sw-rail') === 'tiles' ? 'tiles' : 'rails'));
  const setRailView = useCallback((v: RailView) => { setRailViewS(v); write('sw-rail', v); }, []);
  const [tvOpen, setTvOpen] = useState(false);

  const book: BookId | null = !books.length ? null : account === 'both' ? (books.includes(lastBook) ? lastBook : books[0]) : account;
  // The page decides what the menu says: Overview is always "Both accounts" (even opened by its address), and any
  // other page shows the book it is drawing.
  const shown: Account = onOverview && books.length > 1 ? 'both' : account === 'both' ? (book ?? 'S') : account;
  const mask = useCallback((s: string) => (privacy ? maskMoney(s) : s), [privacy]);

  const value = useMemo(() => ({ book, books, account: shown, pickAccount, privacy, setPrivacy, mask, railView, setRailView, tvOpen, setTvOpen }),
    [book, books, shown, pickAccount, privacy, setPrivacy, mask, railView, setRailView, tvOpen]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useWeb(): WebState {
  const v = useContext(Ctx);
  if (!v) throw new Error('useWeb outside WebStateProvider');
  return v;
}
