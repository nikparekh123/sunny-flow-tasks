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
} from "./ExpectedIncome";
import {
  PutCostCalc,
  pcInitial,
  pcCopy,
  pcDisplay,
  pcFields,
} from "./PutCost";
import {
  IncomeVsCostCalc,
  ivcInitial,
  ivcCopy,
  ivcDisplay,
  ivcFields,
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
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const CALC_MODULES: Record<string, CalcModule<any>> = {
  "pct-diff": {
    component: PercentageDifferenceCalc,
    initial: pctDiffInitial,
    copyText: pctDiffCopy,
    display: pctDiffDisplay,
    payloadFields: pctDiffFields,
  },
  "expected-income": {
    component: ExpectedIncomeCalc,
    initial: eiInitial,
    copyText: eiCopy,
    display: eiDisplay,
    payloadFields: eiFields,
  },
  "put-cost": {
    component: PutCostCalc,
    initial: pcInitial,
    copyText: pcCopy,
    display: pcDisplay,
    payloadFields: pcFields,
  },
  "income-vs-cost": {
    component: IncomeVsCostCalc,
    initial: ivcInitial,
    copyText: ivcCopy,
    display: ivcDisplay,
    payloadFields: ivcFields,
  },
};
