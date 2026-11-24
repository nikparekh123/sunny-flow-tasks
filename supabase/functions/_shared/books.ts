// The books (accounts) every function knows (moved here from sunny-home on 24 Nov 2026 for Together).
/* ⚠ ONE HOME PER BOOK (31 Oct 2026, step 4 of the cousin's book). A build is one book's: every ledger read
   names it, its side rows (reports, account_history, theta_checks) carry it, and its row lands in home_snapshot
   by book_id. start: the book's first day (BOOK_START in build); chart: the first day its charts show; id: its
   home_snapshot id; accounts: how many IBKR accounts make a full day (a day counts once all have reported).
   Book N is the cousin's account (U29584055): $1,000 from 20 Oct 2026, funded with $49,000 on 29 Oct, so it
   starts on 29 Oct (the change line is value less the range's first close, so a deposit inside it reads as a gain). */
export const BOOKS: Record<string, { start: string; chart: string; id: number; accounts: number; name: string; group?: true }> = {
  S: { start: '2026-08-31', chart: '2026-09-01', id: 1, accounts: 2, name: 'Sunny' },   // PNL_GLOSSARY: the stock-replacement shift
  N: { start: '2026-10-29', chart: '2026-10-29', id: 2, accounts: 1, name: 'Nicolay' },
  /* ⚠ TOGETHER (Nik, 24 Nov 2026: "the default view for me will always be Together", a blend of every account; "in case
     I open any further accounts, I have that view"). Book T owns no rows of its own in the ledgers: its build reads
     every real book's (partsOf below, so a new book in this map joins it), matches each book's trades on their own
     (a close in one account never takes an open in another), then adds the same contract up. IBKR's daily values add
     up by day; a day is whole once every book that had started had reported (accounts 1 = whole). Its own rows:
     home_snapshot id 4, home_todo, home_search, reports, account_history, activity_events. Members: the owners of
     every book (book_members T). Chart and start are book S's, the first book. */
  T: { start: '2026-08-31', chart: '2026-09-01', id: 4, accounts: 1, name: 'Together', group: true },
  // The demo book D (2 Nov 2026) was deleted on 6 Nov with its rows, crons and demo_book_roll(); the cousin's
  // login owns book N again. Don't reuse home_snapshot id 3 for anything that expects the old demo rows.
};
/** The real books a book reads: itself, or for Together (T) every book that is not a group. */
export const partsOf = (b: string): string[] => (BOOKS[b]?.group ? Object.keys(BOOKS).filter((k) => !BOOKS[k].group) : [b]);
/** The PostgREST filter on book_id for a book: `eq.S`, or for Together `in.(S,N)`. */
export const bookQ = (b: string): string => { const p = partsOf(b); return p.length > 1 || p[0] !== b ? `in.(${p.join(',')})` : `eq.${b}`; };
