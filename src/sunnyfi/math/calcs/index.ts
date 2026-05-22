/**
 * Math — calculator registry.
 *
 * Each entry maps a calc key (matches CalcMeta.key in data.ts) to a self-
 * contained module: body component, default state, optional copy-as-text
 * formatter, snapshot display, and history preview fields.
 *
 * Adding a calculator is purely additive: drop a module next door and add it
 * here. Calcs not present in this map fall back to <CalcEmpty> in the shell.
 */
import type { ComponentType } from "react";

import {
  PercentageDifferenceCalc,
  pctDiffInitial,
  pctDiffCopy,
  pctDiffDisplay,
  pctDiffFields,
} from "./PercentageDifference";
import {
  ExpectedIncomeCalc,
  eiInitial,
  eiCopy,
  eiDisplay,
  eiFields,
  eiUpsertKey,
  eiRank,
  eiCardLine,
} from "./ExpectedIncome";
import {
  PutCostCalc,
  pcInitial,
  pcCopy,
  pcDisplay,
  pcFields,
  pcUpsertKey,
  pcRank,
  pcCardLine,
} from "./PutCost";
import {
  IncomeVsCostCalc,
  ivcInitial,
  ivcCopy,
  ivcDisplay,
  ivcFields,
  ivcUpsertKey,
  ivcRank,
  ivcCardLine,
} from "./IncomeVsCost";

export interface CalcModule<S extends Record<string, unknown> = Record<string, unknown>> {
  component: ComponentType<{ state: S; setState: (next: S | ((prev: S) => S)) => void }>;
  initial: S;
  /** "Copy as text" payload — null/undefined means the footer button hides. */
  copyText?: (state: S) => string;
  /** Big hero number for the snapshot list row and history preview. */
  display?: (state: S) => { value: string; tone: "neon" | "pos" | "neg" | "muted" };
  /** Input fields surfaced in the History preview grid. */
  payloadFields?: (state: S) => Array<{ label: string; value: string; mono?: boolean }>;
  /** Identity key for upsert-on-save. Returning a string means "saving this
   *  calc with the same key replaces the previous snapshot" (e.g. underlying
   *  ticker). Null means every save creates a new row. */
  upsertKey?: (state: S) => string | null;
  /** Ranking metric for the Compare view's Analyze button. Higher score
   *  always wins — calcs that prefer "lower" (e.g. Put Cost % of notional)
   *  should negate before returning. label = human-readable y-axis name. */
  rank?: (state: S) => { score: number; label: string } | null;
  /** Compact one-line summary for the Compare card mini-header. */
  cardLine?: (state: S) => string;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const CALC_MODULES: Record<string, CalcModule<any>> = {
  "pct-diff": {
    component: PercentageDifferenceCalc,
    initial: pctDiffInitial,
    copyText: pctDiffCopy,
    display: pctDiffDisplay,
    payloadFields: pctDiffFields,
    // Pure-math calc with no concept of ticker → always create new on save,
    // no meaningful "best" ranking either.
    upsertKey: () => null,
    rank: () => null,
  },
  "expected-income": {
    component: ExpectedIncomeCalc,
    initial: eiInitial,
    copyText: eiCopy,
    display: eiDisplay,
    payloadFields: eiFields,
    upsertKey: eiUpsertKey,
    rank: eiRank,
    cardLine: eiCardLine,
  },
  "put-cost": {
    component: PutCostCalc,
    initial: pcInitial,
    copyText: pcCopy,
    display: pcDisplay,
    payloadFields: pcFields,
    upsertKey: pcUpsertKey,
    rank: pcRank,
    cardLine: pcCardLine,
  },
  "income-vs-cost": {
    component: IncomeVsCostCalc,
    initial: ivcInitial,
    copyText: ivcCopy,
    display: ivcDisplay,
    payloadFields: ivcFields,
    upsertKey: ivcUpsertKey,
    rank: ivcRank,
    cardLine: ivcCardLine,
  },
};
