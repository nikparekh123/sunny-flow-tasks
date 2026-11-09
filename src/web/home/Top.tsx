// Home above the numbered sections (README 1, items 1 to 7): the account row with the moment line and tabs, the
// account value, its lines, the chart, ranges and stats, the index strip, (under 1180 px the Positions rail,
// placed by the page), the alert card, then the moment's title, date line and lede.
import { useMemo, type CSSProperties, type ReactNode, type RefObject } from 'react';
import { AccountMenu } from '../components/AccountMenu';
import { clock12, useNY } from '../lib/clock';
import type { J, Tab } from '../lib/data';
import { arrow, C, money } from '../lib/format';
import { useWeb } from '../lib/state';
import { AccountChart } from './top/AccountChart';
import { AlertCard } from './top/AlertCard';
import { alertsFor } from './top/alerts';
import { IndexStrip } from './top/IndexStrip';
import { chartModel, todayChange, weekChange, type Line } from './top/model';
import { Runs, spansOf } from './top/spans';
import { buildStrip } from './top/strip';
import type { TabState } from './top/tabs';

interface Props {
  payload: J;
  /** The brief of the picked moment tab (the live one, or a saved one). */
  doc: J;
  tab: Tab;
  /** The picked tab is the server's current moment. */
  current: boolean;
  tabs: TabState[];
  onTab: (t: Tab) => void;
  /** The Positions rail when it sits in the main column (under 1180 px). */
  railSlot: ReactNode;
  /** Where the numbered sections are drawn (the alert's "See Coming up" scrolls there). */
  sectionsRef: RefObject<HTMLElement>;
}

const COMING = /^(Coming up|Next week|Tomorrow)$/;

export default function Top({ payload, doc, tab, current, tabs, onTab, railSlot, sectionsRef }: Props) {
  const { mask, privacy } = useWeb();
  const now = useNY(15_000);
  const m = useMemo(() => chartModel(payload), [payload]);

  // 1 · The moment line: the moment's name (the brief's title without "Summary", as the design writes it:
  // Pre-market, Market Hours, Post-market, Week in Review) and the live New York time; a saved brief keeps its own
  // time; the weekend reads "Week in Review · markets closed".
  const cap = doc?.dayCaption ?? {};
  const session: string = String(doc?.title ?? cap.session ?? '').replace(/ Summary$/, '');
  const mline = tab === 'weekend'
    ? (/closed/i.test(session) ? session : `${session} · markets closed`)
    : `${session} · ${current ? clock12(now) : String(cap.clock ?? '')}`;

  // 2 · The moment's lines under the value: today in hours and post, the week on the weekend.
  const moment: Line[] = [];
  if (tab === 'open' || tab === 'post') {
    const d = todayChange(m, payload, doc?.built_for, current);
    if (d != null) moment.push({ k: 't', v: `${arrow(d)} ${money(d)}`, c: d < 0 ? C.red : C.green, l: 'today' });
  } else if (tab === 'weekend') {
    const d = weekChange(m, doc?.built_for);
    if (d != null) moment.push({ k: 'w', v: `${arrow(d)} ${money(d)}`, c: d < 0 ? C.red : C.green, l: 'this week' });
  }

  // 5 · The strip.
  const strip = useMemo(() => buildStrip(tab, current, doc, payload, privacy), [tab, current, doc, payload, privacy]);

  // 6 · Alerts, and the section their link scrolls to.
  const alerts = useMemo(() => alertsFor(tab, doc, payload), [tab, doc, payload]);
  const secs: J[] = Array.isArray(doc?.sections) ? doc.sections : [];
  const target = [...secs].reverse().find((s) => COMING.test(String(s?.kicker ?? ''))) ?? null;
  const action = target ? {
    label: `See ${target.kicker}`,
    go: () => {
      const root = sectionsRef.current;
      if (!root) return;
      const re = new RegExp(`(^|·\\s*)${String(target.kicker).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`);
      const hit = Array.from(root.querySelectorAll<HTMLElement>('span,div,p,h2,h3')).find((el) => el.childElementCount === 0 && re.test((el.textContent ?? '').trim()));
      const el = (hit?.closest('section') as HTMLElement | null) ?? hit;
      if (!el) return;
      const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
      window.scrollTo({ top: Math.max(0, el.getBoundingClientRect().top + window.scrollY - 92), behavior: reduce ? 'auto' : 'smooth' });
    },
  } : null;

  // 7 · The lede: the privacy copy when privacy is on (the server writes it without dollars), then the mask.
  const lede = spansOf(privacy ? (doc?.privacy?.lede ?? doc?.lede) : doc?.lede);

  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 20, flexWrap: 'wrap' }}>
        <AccountMenu />
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6, textAlign: 'right' }}>
          <span style={{ fontSize: 22, lineHeight: '28px', fontWeight: 300, letterSpacing: '-.01em', color: 'rgba(245,245,247,.92)' }}>{mline}</span>
          <div role="tablist" aria-label="Moment" style={{ display: 'flex', gap: 12 }}>
            {tabs.map((p) => (
              <button key={p.k} type="button" role="tab" aria-selected={p.on} aria-disabled={!p.enabled} disabled={!p.enabled}
                className="bare" onClick={() => p.enabled && onTab(p.k)}
                style={{ fontSize: 11, lineHeight: '14px', fontWeight: p.on ? 700 : 400, color: p.on ? C.ink : C.ink2, paddingBottom: 2,
                  boxShadow: `inset 0 -1px 0 ${p.on ? C.ink : 'transparent'}`, opacity: p.enabled ? 1 : 0.4, cursor: p.enabled ? 'pointer' : 'default' }}>
                {p.l}
              </button>
            ))}
          </div>
        </div>
      </div>

      <AccountChart payload={payload} moment={moment} />

      <IndexStrip strip={strip} mask={mask} />

      {railSlot}

      <AlertCard alerts={alerts} mask={mask} action={action} />

      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, paddingTop: 44 }}>
        <span style={{ fontSize: 36, lineHeight: '42px', fontWeight: 700, letterSpacing: '-.025em' }}>{doc?.title ?? ''}</span>
        {doc?.dateLine && <span style={{ fontSize: 14, color: C.ink2 }}>{doc.dateLine}</span>}
      </div>
      {lede.length > 0 && (
        <p style={{ margin: '14px 0 0', maxWidth: 860, fontSize: 20, lineHeight: '30px', color: 'rgba(245,245,247,.9)', textWrap: 'pretty' } as CSSProperties}>
          <Runs spans={lede} mask={mask} />
        </p>
      )}
    </>
  );
}
