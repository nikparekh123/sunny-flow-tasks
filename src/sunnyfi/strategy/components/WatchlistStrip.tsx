import type { DragEvent, MouseEvent } from 'react';
import type { WatchingRow } from '../types';
import { fmtPx } from '../calc';
import { encodeDrag, decodeDrag, type DragKind } from './dragdrop';

interface Props {
  items: WatchingRow[];
  dropActive: boolean;
  onDragStart: (kind: DragKind, ticker: string) => void;
  onDragEnd: () => void;
  onDelete: (ticker: string) => void;
  onAdd: () => void;
  onDropFromBucket: (ticker: string) => void;
}

export function WatchlistStrip({
  items,
  dropActive,
  onDragStart,
  onDragEnd,
  onDelete,
  onAdd,
  onDropFromBucket,
}: Props) {
  return (
    <div
      className={'watch-strip' + (dropActive ? ' drop-active' : '')}
      onDragOver={(e) => {
        if (dropActive) e.preventDefault();
      }}
      onDrop={(e) => {
        e.preventDefault();
        const decoded = decodeDrag(e.dataTransfer.getData('text/plain'));
        if (decoded?.kind === 'pos') onDropFromBucket(decoded.ticker);
      }}
    >
      <div className="head">
        <span className="title">Watchlist</span>
        <span className="count">{items.length} tracked</span>
        <span className="drop-hint">drop here to sell — opens close position modal</span>
        <span className="hint">
          drag <span className="key">▸</span> onto a bucket below to buy
        </span>
      </div>
      <div className="watch-row">
        {items.map((s) => (
          <div
            key={s.ticker}
            className="watch-card"
            draggable
            onDragStart={(e: DragEvent<HTMLDivElement>) => {
              e.dataTransfer.setData('text/plain', encodeDrag('watch', s.ticker));
              e.dataTransfer.effectAllowed = 'move';
              onDragStart('watch', s.ticker);
              e.currentTarget.classList.add('dragging');
            }}
            onDragEnd={(e: DragEvent<HTMLDivElement>) => {
              e.currentTarget.classList.remove('dragging');
              onDragEnd();
            }}
            title={`${s.name ?? s.ticker} · ${s.sector}`}
          >
            <button
              className="del"
              onClick={(e: MouseEvent<HTMLButtonElement>) => {
                e.stopPropagation();
                onDelete(s.ticker);
              }}
              title="remove from watchlist"
            >
              ✕
            </button>
            <div className="row">
              <span className="tk">{s.ticker}</span>
              <span className="px">
                {s.current_price != null ? fmtPx(s.current_price) : '—'}
              </span>
            </div>
            <div className="row">
              <span className="name">{s.name ?? s.ticker}</span>
              <span className="sector">{s.sector}</span>
            </div>
          </div>
        ))}
        <button className="watch-add" onClick={onAdd}>
          <span className="plus">+</span>
          add
        </button>
      </div>
    </div>
  );
}
