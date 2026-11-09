// Home (handoff 2026-11-08-web, README 1): the main column (flex 1 1 760px) and the Positions rail on the right
// (flex 0 0 340px, sticky at 92 px, its own scroll), 48 apart. Under 1180 px of content width the rail leaves the
// side and sits in the main column after the index strip, as a full-width Positions section (padding-top 40).
// The moment tabs pick which brief the page reads: the live one, or the last saved brief of another moment.
import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { AccountMenu } from '../components/AccountMenu';
import Rail from '../home/Rail';
import Sections from '../home/Sections';
import Top from '../home/Top';
import { tabStates } from '../home/top/tabs';
import { TAB_OF, useBriefLog, useHome, type Tab } from '../lib/data';
import { useWeb } from '../lib/state';
import { NARROW_QUERY } from '../WebLayout';

const subscribe = (cb: () => void) => {
  const mq = window.matchMedia(NARROW_QUERY);
  mq.addEventListener('change', cb);
  return () => mq.removeEventListener('change', cb);
};
const narrowNow = () => window.matchMedia(NARROW_QUERY).matches;

export default function Home() {
  const { book } = useWeb();
  const home = useHome(book);
  const log = useBriefLog(book);
  const narrow = useSyncExternalStore(subscribe, narrowNow, () => false);
  const secRef = useRef<HTMLDivElement>(null);

  const payload = home.data?.payload;
  const curDoc = payload?.brief?.doc;
  const cur: Tab = TAB_OF[String(curDoc?.moment ?? '')] ?? 'pre';
  const [picked, setPicked] = useState<Tab | null>(null);
  // A new moment or another book opens on the live brief.
  useEffect(() => { setPicked(null); }, [cur, book]);

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

  const rail = narrow ? (
    <section aria-label="Positions" style={{ display: 'flex', flexDirection: 'column', paddingTop: 40 }}>
      <Rail payload={payload} book={book} narrow />
    </section>
  ) : null;

  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 48, alignItems: 'flex-start' }}>
      <main style={{ flex: '1 1 760px', minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <Top payload={payload} doc={doc} tab={tab} current={current} tabs={tabStates(cur, curDoc, log.data, tab, payload.calendar)}
          onTab={(t) => setPicked(t === cur ? null : t)} railSlot={rail} sectionsRef={secRef} />
        <div ref={secRef} style={{ display: 'flex', flexDirection: 'column' }}>
          <Sections doc={doc} payload={payload} book={book} />
        </div>
      </main>
      {!narrow && (
        <aside aria-label="Positions" className="noscroll"
          style={{ flex: '0 0 340px', position: 'sticky', top: 92, maxHeight: 'calc(100vh - 112px)', overflowY: 'auto', minWidth: 0, display: 'flex', flexDirection: 'column' }}>
          <Rail payload={payload} book={book} narrow={false} />
        </aside>
      )}
    </div>
  );
}
