import { useEffect, useState } from 'react';
import { Sliders, X } from 'lucide-react';

type Density = 'compact' | 'default' | 'spacious';
type Accent = 'neon' | 'ember' | 'violet';

const STORAGE_KEY = 'owl-tweaks';

interface Tweaks {
  density: Density;
  accent: Accent;
}

const DEFAULTS: Tweaks = { density: 'default', accent: 'neon' };

function load(): Tweaks {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULTS;
    const parsed = JSON.parse(raw) as Partial<Tweaks>;
    return { ...DEFAULTS, ...parsed };
  } catch {
    return DEFAULTS;
  }
}

function apply({ density, accent }: Tweaks) {
  const body = document.body;
  body.classList.remove('owl-density-compact', 'owl-density-spacious');
  if (density === 'compact') body.classList.add('owl-density-compact');
  if (density === 'spacious') body.classList.add('owl-density-spacious');
  body.classList.remove('owl-accent-ember', 'owl-accent-violet');
  if (accent === 'ember') body.classList.add('owl-accent-ember');
  if (accent === 'violet') body.classList.add('owl-accent-violet');
}

export function TweaksPanel() {
  const [tweaks, setTweaks] = useState<Tweaks>(() => load());
  const [open, setOpen] = useState(false);

  useEffect(() => {
    apply(tweaks);
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(tweaks));
    } catch {}
  }, [tweaks]);

  return (
    <>
      <button
        onClick={() => setOpen((o) => !o)}
        className="fixed bottom-4 right-4 z-40 inline-flex items-center justify-center rounded-full transition-colors"
        style={{
          width: 38,
          height: 38,
          background: 'var(--owl-dash)',
          border: '1px solid var(--owl-line-bright)',
          color: 'var(--owl-text-secondary)',
          boxShadow: '0 6px 20px rgba(0,0,0,0.3)',
        }}
        aria-label="Tweaks"
      >
        <Sliders className="w-4 h-4" />
      </button>

      {open && (
        <div
          className="fixed bottom-[60px] right-4 z-40 rounded-xl p-4"
          style={{
            width: 260,
            background: 'var(--owl-dash)',
            border: '1px solid var(--owl-line-bright)',
            boxShadow: '0 10px 30px rgba(0,0,0,0.4)',
          }}
        >
          <div className="flex items-center justify-between mb-[10px]">
            <h4
              style={{
                fontSize: 11,
                fontWeight: 600,
                letterSpacing: '2.5px',
                textTransform: 'uppercase',
                color: 'var(--owl-neon)',
              }}
            >
              Tweaks
            </h4>
            <button
              onClick={() => setOpen(false)}
              style={{ color: 'var(--owl-text-muted)' }}
              aria-label="Close"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>

          <Row label="Density">
            <Seg
              value={tweaks.density}
              options={[
                { v: 'compact', l: 'Compact' },
                { v: 'default', l: 'Comfy' },
                { v: 'spacious', l: 'Spacious' },
              ]}
              onChange={(v) => setTweaks((t) => ({ ...t, density: v as Density }))}
            />
          </Row>

          <Row label="Accent">
            <Seg
              value={tweaks.accent}
              options={[
                { v: 'neon', l: 'Neon' },
                { v: 'ember', l: 'Ember' },
                { v: 'violet', l: 'Violet' },
              ]}
              onChange={(v) => setTweaks((t) => ({ ...t, accent: v as Accent }))}
            />
          </Row>
        </div>
      )}
    </>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div
      className="flex items-center justify-between py-[6px]"
      style={{
        borderBottom: '1px solid var(--owl-line)',
        fontSize: 12,
        color: 'var(--owl-text-secondary)',
      }}
    >
      <span>{label}</span>
      {children}
    </div>
  );
}

function Seg({
  value,
  options,
  onChange,
}: {
  value: string;
  options: { v: string; l: string }[];
  onChange: (v: string) => void;
}) {
  return (
    <div
      className="inline-flex rounded-md p-[2px]"
      style={{ background: 'rgba(15,51,51,0.7)' }}
    >
      {options.map((o) => {
        const on = o.v === value;
        return (
          <button
            key={o.v}
            onClick={() => onChange(o.v)}
            className="rounded-sm transition-colors"
            style={{
              fontSize: 11,
              padding: '3px 8px',
              background: on ? 'var(--owl-elevated)' : 'transparent',
              color: on ? 'var(--owl-text-primary)' : 'var(--owl-text-muted)',
            }}
          >
            {o.l}
          </button>
        );
      })}
    </div>
  );
}
