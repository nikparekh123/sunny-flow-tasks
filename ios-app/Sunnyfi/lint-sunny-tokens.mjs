#!/usr/bin/env node
/**
 * Sunny token lint, Swift edition.
 *
 * handoff/lint-tokens.mjs walks .css/.ts/.tsx/.js/.jsx/.html/.svelte/.vue and so
 * cannot see a SwiftUI codebase at all. This ports the same rule: SPEC 00, no
 * literal values in component code. Every number and colour must come from
 * SunnyTokens.swift, which is the transcription of handoff/tokens.css.
 *
 *   node lint-sunny-tokens.mjs Sunnyfi/Redesign
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname, basename } from 'node:path';

const ROOT = process.argv[2] || 'Sunnyfi/Redesign';
const TOKENS = join(ROOT, 'SunnyTokens.swift');
const src = readFileSync(TOKENS, 'utf8');

// every number that legitimately exists, harvested from the token file
const legal = new Set([...src.matchAll(/-?\d+(?:\.\d+)?/g)].map(m => m[0]));
// structurally free: identity values with no visual weight
['0', '1', '2', '0.0', '1.0', '2', '100', '255', '3'].forEach(n => legal.add(n));

// numbers only matter where they set geometry or type
const CTX = /\.(frame|padding|spacing|offset|cornerRadius|lineWidth|tracking|kerning|scaleEffect|blur|shadow)\s*\(|EdgeInsets\(|CGSize\(|\.font\(|size:\s|width:\s|height:\s/;

function walk(d, out = []) {
  for (const n of readdirSync(d)) {
    const p = join(d, n);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (extname(n) === '.swift') out.push(p);
  }
  return out;
}

const bad = [];
for (const file of walk(ROOT)) {
  if (basename(file) === 'SunnyTokens.swift') continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    const t = line.trim();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return;
    const at = `${file}:${i + 1}`;

    for (const m of line.matchAll(/0x[0-9A-Fa-f]{6}/g))
      bad.push([at, `colour ${m[0]} is not a token`, t]);

    if (CTX.test(line)) {
      for (const m of line.matchAll(/(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])/g)) {
        if (!legal.has(m[1])) bad.push([at, `length ${m[1]} is not a token`, t]);
      }
    }
    if (/\.border\(/.test(line))
      bad.push([at, 'border used as a rule — use a child view with a height (SPEC 04)', t]);
    if (/Color\(red:|Color\(white:|UIColor\(/.test(line) && !/shadowInk/.test(line))
      bad.push([at, 'raw colour — use a token', t]);
  });
}

if (!bad.length) { console.log('✓ tokens clean'); process.exit(0); }
console.error(`\n${bad.length} token violation${bad.length > 1 ? 's' : ''}:\n`);
for (const [w, why, s] of bad) console.error(`  ${w}\n    ${why}\n    ${s}\n`);
process.exit(1);
