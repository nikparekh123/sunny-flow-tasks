// The Income tab (handoff 2026-11-24 late §1.1, Current Web: SunnyIncome only="banner" banner="bars" part="page", then
// SunnyIncomeCal head=false view="w" quiet="fold"): the title "Income" (28/34 bold, nothing under it) with the realized
// banner 18 px under it (Banner.tsx), then the calendar 24 px below (IncomeCalendar.tsx), max width 1240. The calendar
// replaced the logo strip, the totals row and the card a name (Nik, 24 Nov 2026). Both follow the account menu;
// privacy reaches the banner only (the calendar has no dollar figures).
// Every figure is the Home payload's `income` (sunny-home income.ts) for the account on screen; Together carries both.
import { useMemo } from 'react';
import { useHome, type J } from '../lib/data';
import { useWeb } from '../lib/state';
import { Banner } from '../income/Banner';
import { IncomeCalendar } from '../income/IncomeCalendar';
import { readIncome } from '../income/model';

export default function Income() {
  const { book } = useWeb();
  const home = useHome(book);
  const payload: J = home.data?.payload;
  const inc = useMemo(() => readIncome(payload), [payload]);
  const accounts = useMemo(() => {
    if (book !== 'T') return null;
    const sp: J[] = Array.isArray(payload?.split) ? payload.split : [];
    return sp.length > 1 ? sp.map((s) => String(s.name ?? s.id)) : ['Sunny', 'Nicolay'];
  }, [book, payload]);

  return (
    <div aria-busy={!payload} style={{ display: 'flex', flexDirection: 'column', gap: 24, maxWidth: 1240 }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
        <h1 style={{ margin: 0, fontSize: 28, lineHeight: '34px', fontWeight: 700, letterSpacing: '-.02em' }}>Income</h1>
        {inc?.banner && <Banner b={inc.banner} today={inc.today} accounts={accounts} />}
      </div>
      {inc && book && <IncomeCalendar inc={inc} payload={payload} book={book} />}
    </div>
  );
}
