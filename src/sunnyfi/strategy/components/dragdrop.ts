// Kind-aware drag payloads used across the Strategy board.
// Format: "kind:ticker" stored on dataTransfer text/plain.

export type DragKind = 'watch' | 'unassigned' | 'pos';

export interface DragState {
  kind: DragKind;
  ticker: string;
  from?: string;
}

export function encodeDrag(kind: DragKind, ticker: string): string {
  return `${kind}:${ticker}`;
}

export function decodeDrag(data: string): { kind: DragKind; ticker: string } | null {
  if (!data) return null;
  const i = data.indexOf(':');
  if (i < 0) return null;
  const kind = data.slice(0, i) as DragKind;
  if (kind !== 'watch' && kind !== 'unassigned' && kind !== 'pos') return null;
  return { kind, ticker: data.slice(i + 1) };
}
