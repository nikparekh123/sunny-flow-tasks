// Overview §3 · Coming up across both books (SunnyOverview 165): this week to Friday, then later. The server words
// every event (sunny-home together.ts); the first five show, the rest behind "Show all N".
import { useState } from 'react';
import { C } from '../lib/format';
import { useWeb } from '../lib/state';
import { H2, LINE } from './ui';
import type { Together } from './together';

export function ComingUp({ t }: { t: Together }) {
  const { mask } = useWeb();
  const [all, setAll] = useState(false);
  const evs = t.events, shown = all ? evs : evs.slice(0, 5);
  const groups = ([[true, 'This week'], [false, 'Later']] as [boolean, string][])
    .map(([w, l]) => ({ k: w ? 'wk' : 'later', l, items: shown.filter((e) => !!e.week === w) }))
    .filter((g) => g.items.length);
  return (
    <section aria-label="Coming up" style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
      <div style={{ paddingBottom: 4 }}><H2>Coming up</H2></div>
      {groups.map((g) => (
        <div key={g.k} role="list" aria-label={g.l} style={{ display: 'flex', flexDirection: 'column', paddingTop: 10 }}>
          <span style={{ paddingBottom: 6, fontSize: 13, lineHeight: '18px', fontWeight: 600, color: C.ink2 }}>{g.l}</span>
          {g.items.map((e) => (
            <div key={`${e.d}|${e.kind}|${e.t ?? ''}|${e.title}`} role="listitem"
              style={{ display: 'grid', gridTemplateColumns: '56px minmax(0,1fr)', gap: 12, alignItems: 'center', padding: '10px 0', borderTop: LINE }}>
              <span style={{ display: 'flex', flexDirection: 'column' }}>
                <span style={{ fontSize: 12, lineHeight: '16px', fontWeight: 600, color: C.ink2 }}>{e.wd}</span>
                <span style={{ fontSize: 15, lineHeight: '20px', fontWeight: 700, whiteSpace: 'nowrap' }}>{e.md}</span>
              </span>
              <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                <span style={{ fontSize: 16, lineHeight: '21px', fontWeight: 600 }}>{e.title}</span>
                {e.sub && <span style={{ fontSize: 13, lineHeight: '18px', fontWeight: 500, color: C.ink2, textWrap: 'pretty' } as React.CSSProperties}>{mask(e.sub)}</span>}
              </span>
            </div>
          ))}
        </div>
      ))}
      {evs.length > 5 && (
        <button type="button" className="bare ov-tap" aria-expanded={all} onClick={() => setAll((a) => !a)}
          style={{ alignSelf: 'flex-start', display: 'flex', alignItems: 'center', minHeight: 44, fontSize: 15, lineHeight: '20px', fontWeight: 600, color: C.ink }}>
          {all ? 'Show fewer' : `Show all ${evs.length}`}
        </button>
      )}
    </section>
  );
}
