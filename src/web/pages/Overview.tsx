// Overview · Both accounts (handoff 2026-11-18 §4, SunnyOverview 165; Nik, 17 Nov 2026: "the Overview should read
// like Sunny and Nicolay combined, no scores"). Opened from the account menu's "Both accounts".
//
// Every figure is the server's: sunny-home builds `together` in book S's build from both books (together.ts): the
// two accounts as one value line, Your positions by what you hold, Coming up across both books, and Realized P&L
// by month with its trend. The page only lays it out: fluid width, and on a wide page Your positions, Coming up and
// Realized P&L sit side by side, wrapping to one column when narrow. Allocation is gone (Nov 17); the page ends
// with Realized P&L.
import { useMemo } from 'react';
import { AccountMenu } from '../components/AccountMenu';
import { useHome } from '../lib/data';
import { useWeb } from '../lib/state';
import { ComingUp } from '../overview/ComingUp';
import { RealizedPL } from '../overview/RealizedPL';
import { TogetherChart } from '../overview/ValueChart';
import { YourPositions } from '../overview/YourPositions';
import { readTogether } from '../overview/together';

export default function Overview() {
  const { books } = useWeb();
  const hs = useHome(books.includes('S') ? 'S' : null);
  const t = useMemo(() => readTogether(hs.data?.payload), [hs.data?.payload]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 28 }}>
      <div style={{ alignSelf: 'flex-start' }}><AccountMenu /></div>
      {t && (
        <div className="tnum" style={{ containerType: 'inline-size', display: 'flex', flexDirection: 'column', gap: 40 }}>
          <TogetherChart t={t} />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(min(100%,340px),1fr))', gap: '40px 48px', alignItems: 'start' }}>
            {t.positions.length > 0 && <YourPositions t={t} />}
            {t.events.length > 0 && <ComingUp t={t} />}
            <RealizedPL t={t} />
          </div>
        </div>
      )}
      <style>{'.sw .ov-tap:active{opacity:.6}.sw .ov-rg:hover > span{color:#F5F5F7!important}'}</style>
    </div>
  );
}
