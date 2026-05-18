import { useEffect, type CSSProperties, type ReactNode } from 'react';

interface Props {
  accent?: string;
  compact?: boolean;
  onClose: () => void;
  children: ReactNode;
}

export function Modal({ accent = 'var(--navi-neon)', compact, onClose, children }: Props) {
  useEffect(() => {
    const k = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', k);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', k);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  const style = { '--accent': accent } as CSSProperties;
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className={'modal' + (compact ? ' compact' : '')}
        style={style}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}
