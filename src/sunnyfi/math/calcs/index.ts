/**
 * Math — calculator registry.
 *
 * Each entry maps a calc key (matches CalcMeta.key in data.ts) to a self-
 * contained module: body component, default state, optional copy-as-text
 * formatter, optional display value for the snapshot tag / history.
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
};
