// The alert card (README 1, item 6): G1 glass, one alert at a time, ✕ dismisses it for the session, ‹ 1 of 3 ›
// pages, and Earnings season and Holiday link to the brief's Coming up section.
import { useEffect, useState } from 'react';
import { C } from '../../lib/format';
import type { Alert } from './alerts';

const KEY = 'sw-alerts-dismissed';
const readDismissed = (): string[] => { try { return JSON.parse(sessionStorage.getItem(KEY) ?? '[]'); } catch { return []; } };

export function AlertCard({ alerts, mask, action }: { alerts: Alert[]; mask: (s: string) => string; action: { label: string; go: () => void } | null }) {
  const [dis, setDis] = useState<string[]>(readDismissed);
  const [ai, setAi] = useState(0);
  const vis = alerts.filter((a) => !dis.includes(a.key));
  const sig = vis.map((a) => a.key).join(',');
  useEffect(() => { setAi(0); }, [sig]);
  if (!vis.length) return null;
  const i = Math.min(ai, vis.length - 1), a = vis[i], many = vis.length > 1;
  const dismiss = () => {
    const next = [...dis, a.key];
    setDis(next);
    try { sessionStorage.setItem(KEY, JSON.stringify(next)); } catch { /* private window */ }
  };
  const act = a.linked ? action : null;
  return (
    <div role="region" aria-label="Alert" className="g1"
      style={{ marginTop: 24, borderRadius: 20, padding: '16px 18px 14px 22px', display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', gap: '6px 16px' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
        <span style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, fontWeight: 600, color: C.ink3 }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: a.dot }} />{mask(a.kick)}
        </span>
        <span style={{ fontSize: 17, lineHeight: '23px', fontWeight: 600 }}>{mask(a.t)}</span>
        {a.s && <span style={{ fontSize: 14, lineHeight: '20px', color: C.ink2 }}>{mask(a.s)}</span>}
      </div>
      <button type="button" className="bare" onClick={dismiss} aria-label="Dismiss"
        style={{ alignSelf: 'start', width: 28, height: 28, borderRadius: '50%', background: 'rgba(118,118,128,.24)', display: 'flex',
          alignItems: 'center', justifyContent: 'center', fontSize: 11, color: C.ink3 }}>✕</button>
      <div style={{ gridColumn: '1 / -1', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, paddingTop: 4 }}>
        {act && (
          <button type="button" className="bare" onClick={act.go} style={{ fontSize: 14, fontWeight: 600, color: C.green }}>{act.label} ›</button>
        )}
        <span style={{ flex: 1 }} />
        {many && (
          <span className="tnum" style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: C.ink2 }}>
            <button type="button" className="bare" onClick={() => setAi(Math.max(0, i - 1))} aria-label="Previous alert" disabled={i === 0}
              style={{ padding: '2px 8px', fontSize: 16, opacity: i > 0 ? 1 : 0.3 }}>‹</button>
            {i + 1} of {vis.length}
            <button type="button" className="bare" onClick={() => setAi(Math.min(vis.length - 1, i + 1))} aria-label="Next alert" disabled={i === vis.length - 1}
              style={{ padding: '2px 8px', fontSize: 16, opacity: i < vis.length - 1 ? 1 : 0.3 }}>›</button>
          </span>
        )}
      </div>
    </div>
  );
}
