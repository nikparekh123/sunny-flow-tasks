// Overview's segmented controls (Six checks period, Allocation view), exactly as the design draws them: a capsule
// track (rgba(118,118,128,.24), padding 2, gap 2) of 14/18 segments, padding 6 14, the selected one glass.
const SG = 'inset 0 0 0 .5px rgba(255,255,255,.22),inset 0 1px 0 rgba(255,255,255,.3),0 2px 8px rgba(0,0,0,.35)';

export function Seg<K extends string>({ items, value, onChange, label }: {
  items: [K, string][]; value: K; onChange: (k: K) => void; label: string;
}) {
  return (
    <div role="radiogroup" aria-label={label}
      style={{ display: 'flex', gap: 2, padding: 2, borderRadius: 999, background: 'rgba(118,118,128,.24)' }}>
      {items.map(([k, l]) => {
        const on = k === value;
        return (
          <button key={k} type="button" role="radio" aria-checked={on} className="bare" onClick={() => onChange(k)}
            style={{ cursor: 'pointer', padding: '6px 14px', borderRadius: 999, fontSize: 14, lineHeight: '18px', fontWeight: on ? 600 : 500,
              color: on ? '#FFFFFF' : '#F5F5F7', background: on ? 'rgba(255,255,255,.20)' : 'transparent', boxShadow: on ? SG : 'none',
              whiteSpace: 'nowrap', transition: 'background .25s cubic-bezier(.22,1,.36,1)' }}>
            {l}
          </button>
        );
      })}
    </div>
  );
}
