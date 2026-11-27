// The Sundial tab (handoff 2026-11-27 README §1-§2): Income is called Sundial; the tab is the five-column board
// (sundial/Board.tsx), web 207a, and under 960 px of content the phone layout (207c). The realized banner and the
// calendar left the tab (README §5). The board follows the account menu: Nicolay = Sundial's book (NVDA, SpaceX),
// Together = both books, Sunny = his names once Sundial covers them (empty until then; Nik 27 Nov: NVDA and SpaceX only).
import { useEffect, useRef, useState } from 'react';
import { useBoard } from '../lib/data';
import { useWeb } from '../lib/state';
import { Board } from '../sundial/Board';

const NARROW_UNDER = 960;

export default function Sundial() {
  const { book, mask } = useWeb();
  const [tk, setTk] = useState('all');
  useEffect(() => setTk('all'), [book]);
  const q = useBoard(book, tk);
  const box = useRef<HTMLDivElement>(null);
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setNarrow(e.contentRect.width < NARROW_UNDER));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return (
    <div ref={box} aria-busy={!q.data} style={{ maxWidth: 1440 }}>
      <Board data={q.data} narrow={narrow} tk={tk} setTk={setTk} mask={mask} />
      {q.isError && !q.data && <p style={{ marginTop: 24, fontSize: 15, color: '#8C8C8C' }}>Sundial is not answering. It tries again in a minute.</p>}
    </div>
  );
}
