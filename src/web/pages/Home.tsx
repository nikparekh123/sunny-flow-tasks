// Home (handoff 2026-11-08-web, README 1; handoff 2026-11-24 §3): the main column (flex 1 1 480px) and, from 960 px of
// content width, the right rail (flex 0 0 340px, sticky at 92 px, its own scroll), 48 apart. The rail is Income today
// only (§3: it replaces the Positions block; Positions stays a tab). Under 960 px Income today leaves the side and
// sits in the main column after the index strip, wide, before the alert and the sections (padding-top 40).
// The moment tabs pick which brief the page reads: the live one, or the last saved brief of another moment.
import { useEffect, useMemo, useRef, useState } from 'react';
import { AccountMenu } from '../components/AccountMenu';
import { useContentWidth } from '../home/blocks/width';
import Sections from '../home/Sections';
import Top from '../home/Top';
import { tabStates } from '../home/top/tabs';
import { IncomeToday } from '../income/IncomeToday';
import { TAB_OF, useBriefLog, useHome, usePrefetchFromHome, type J, type Tab } from '../lib/data';
import { useWeb } from '../lib/state';

/** The rail takes the side from this much content width (Current Web `nar2`). */
const RAIL_FROM = 960;

export default function Home() {
  const { book } = useWeb();
  const home = useHome(book);
  const log = useBriefLog(book);
  const cw = useContentWidth();
  // Before the page frame is measured: the window less the frame's 48 px sides.
  const width = cw || (typeof window !== 'undefined' ? Math.min(1344, window.innerWidth - 96) : 1344);
  const side = width >= RAIL_FROM;
  const secRef = useRef<HTMLDivElement>(null);

  const payload = home.data?.payload;
  const curDoc = payload?.brief?.doc;
  const cur: Tab = TAB_OF[String(curDoc?.moment ?? '')] ?? 'pre';
  const [picked, setPicked] = useState<Tab | null>(null);
  // A new moment or another book opens on the live brief.
  useEffect(() => { setPicked(null); }, [cur, book]);

  // Once Home is up, read ahead what its clicks open: each name held on Positions, then its ticker page.
  const held = useMemo(() => ((payload?.brief?.names ?? []) as J[]).map((n) => String(n.t)).filter(Boolean), [payload]);
  usePrefetchFromHome(book, held, held.length > 0);

  if (!book || !payload) {
    return (
      <div aria-busy={home.isLoading || !book} style={{ display: 'flex', flexDirection: 'column' }}>
        <AccountMenu />
      </div>
    );
  }

  const tabs = tabStates(cur, curDoc, log.data, picked ?? cur, payload.calendar);
  const want = picked ?? cur;
  const tab: Tab = tabs.find((t) => t.k === want)?.enabled ? want : cur;
  const current = tab === cur;
  const doc = current ? curDoc : log.data?.[tab]?.doc ?? curDoc;

  const inMain = side ? null : (
    <div style={{ display: 'flex', flexDirection: 'column', paddingTop: 40 }}>
      <IncomeToday payload={payload} narrow={false} />
    </div>
  );

  return (
    <div style={{ display: 'flex', gap: 48, alignItems: 'flex-start' }}>
      <main style={{ flex: '1 1 480px', minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <Top payload={payload} doc={doc} tab={tab} current={current} tabs={tabStates(cur, curDoc, log.data, tab, payload.calendar)}
          onTab={(t) => setPicked(t === cur ? null : t)} railSlot={inMain} sectionsRef={secRef} />
        <div ref={secRef} style={{ display: 'flex', flexDirection: 'column' }}>
          <Sections doc={doc} payload={payload} book={book} />
        </div>
      </main>
      {side && (
        <aside aria-label="Income" className="noscroll"
          style={{ flex: '0 0 340px', position: 'sticky', top: 92, maxHeight: 'calc(100vh - 112px)', overflowY: 'auto', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 28 }}>
          <IncomeToday payload={payload} narrow />
        </aside>
      )}
    </div>
  );
}
