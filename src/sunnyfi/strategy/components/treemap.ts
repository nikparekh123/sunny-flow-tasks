// Treemap layout — direct port of swm-app.jsx treemapLayout().

import type { StrategyPosition } from '../types';
import { calcPosition, type Cadence, type PositionCalc } from '../calc';

export interface TreemapItem {
  p: StrategyPosition;
  c: PositionCalc;
  sizeClass: '' | 'big' | 'wide';
}

export interface TreemapLayout {
  gridClass: 'n2' | 'n3' | 'n4';
  items: TreemapItem[];
}

export function treemapLayout(
  positions: StrategyPosition[],
  cadence: Cadence,
): TreemapLayout {
  const enriched = positions.map((p) => ({
    p,
    c: calcPosition(p, cadence),
    sizeClass: '' as const,
  }));
  const sorted = [...enriched].sort((a, b) => b.c.cost - a.c.cost);
  const n = sorted.length;
  if (n <= 1) return { gridClass: 'n2', items: sorted };
  if (n === 2) {
    return {
      gridClass: 'n2',
      items: [
        { ...sorted[0], sizeClass: 'big' },
        { ...sorted[1], sizeClass: 'wide' },
      ],
    };
  }
  if (n === 3) {
    return {
      gridClass: 'n3',
      items: [
        { ...sorted[0], sizeClass: 'big' },
        { ...sorted[1], sizeClass: '' },
        { ...sorted[2], sizeClass: '' },
      ],
    };
  }
  return { gridClass: 'n4', items: sorted };
}
