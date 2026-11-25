// The focus look (handoff 2026-11-25-focus, Nik 25 Nov 2026: "the colours are too harsh and pop too much; see how
// Tesla does it; a hero and the rest info; not every value needs attention; keep the bars in colour").
// Palette: page #171717, raised #212121 (raised-2 #2A2A2A / #383838), chip-on #424242, text #F2F2F2, text-2 #AAAAAA,
// grey #8C8C8C, grey-3 #636363, white-fill #FAFAFA; red #E82127 and green #4CBB6C on marks only; orange #E8A33D and
// yellow #FCC00A for chart levels; calls #3E6AE1 and puts #C8946A on fills only.
// Rules (README §2):
//   2.1 No colour on words: text and numbers are never red, green, orange, yellow or blue; INK at 15 px and up,
//       GREY under 15 (`word(fs)`).
//   2.2 A gain or loss carries a sign: + up, − (U+2212) down, neutral (`signed`). Not when an arrow or sign is there.
//   2.3 A warning or an action keeps an 8 px dot 7 px before it (`<Dot k="r|g" />`): red danger, green ready to act;
//       only on words or numbers 20 px and up; never orange or watch; never when its arrow says up or down; never in
//       a coloured pill. Rare.
//   2.4 Colour lives on marks (dots, pills with a word, rings, strike lines, chart lines) and on the bars (calls and
//       puts fills). Calls and puts on words and thin lines go grey (CALLS_W, PUTS_W). Large red or green fills with
//       no text go FILL #707070, switches "on" too. Kept in colour on Nik's word (25 Nov): the sector heatmap tiles
//       and the Realized P&L bars.
//   2.5 Bold (600 and up) only on text 20 px and up; under 20: 500 at 14 px and up, 400 under 14. Small capital
//       labels become plain words: as written, no letter-spacing, 13 px, 500, GREY (`label`).
//   2.6 A chip that is on, in a row of 3 or more, is CHIP_ON with INK words. The one primary action stays white.
import type { CSSProperties } from 'react';

export const PAGE = '#171717', RAISED = '#212121', RAISED2 = '#2A2A2A', RAISED3 = '#383838', CHIP_ON = '#424242';
export const INK = '#F2F2F2', INK2 = '#AAAAAA', GREY = '#8C8C8C', GREY3 = '#636363', WHITE_FILL = '#FAFAFA';
export const RED = '#E82127', GREEN = '#4CBB6C', ORANGE = '#E8A33D', YELLOW = '#FCC00A';
export const CALLS = '#3E6AE1', PUTS = '#C8946A', CALLS_W = '#BEBEBE', PUTS_W = '#969696';
export const FILL = '#707070';
export const LEVEL = '#AAAAAA', LEVEL_LABEL = '#C8C8C8';

/** Text colour by size: INK at 15 px and up, GREY under. */
export const word = (fs: number) => (fs >= 15 ? INK : GREY);

/** "+$800", "−$4.3K", "+29.6%": the sign of `v` before an unsigned figure (zero, or a figure already signed, as is). */
export const signed = (v: number, figure: string) =>
  /^[+\-−▲▼↑↓↗↘±]/.test(figure) ? figure : v > 0 ? `+${figure}` : v < 0 ? `−${figure}` : figure;

/** A small capital label as Tesla writes it: plain words, 13 px, 500, grey. */
export const label: CSSProperties = { fontSize: 13, lineHeight: '18px', fontWeight: 500, color: GREY };

/** The 8 px warning dot, 7 px before its value, vertically centred: r danger, g ready to act. */
export function Dot({ k }: { k: 'r' | 'g' }) {
  return <span aria-hidden="true" style={{ display: 'inline-block', flex: 'none', width: 8, height: 8, borderRadius: '50%', background: k === 'r' ? RED : GREEN, marginRight: 7, verticalAlign: '.08em', alignSelf: 'center' }} />;
}
