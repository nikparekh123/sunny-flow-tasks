import { useState, useEffect, useRef } from 'react';
import { toast } from 'sonner';
import { SECTORS, fmtQty, fmtUSD2 } from './types';
import type { PositionInput, StrategyBucket } from './usePositions';

const STRATEGY_ALIASES: Record<string, StrategyBucket> = {
  income: 'income',
  invest: 'invest',
  investment: 'invest',
  yield: 'yield',
};

interface Props {
  open: boolean;
  onClose: () => void;
  onConfirm: (rows: PositionInput[]) => Promise<void>;
}

type Stage = 'pick' | 'validating' | 'preview' | 'error' | 'saving';

const VALID_SECTORS = new Set<string>(SECTORS);

interface ValidationError {
  row: number;
  field: string;
  msg: string;
}
interface ParseResult {
  rows: PositionInput[];
  errors: ValidationError[];
}

function parseCsv(text: string): ParseResult {
  const lines = text
    .replace(/^﻿/, '')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .trim()
    .split('\n')
    .filter((l) => l.trim().length > 0);

  const errors: ValidationError[] = [];
  if (lines.length === 0) {
    errors.push({ row: 0, field: '', msg: 'empty file' });
    return { rows: [], errors };
  }

  const split = (line: string): string[] => {
    const out: string[] = [];
    let cur = '';
    let inQ = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (c === '"') { inQ = !inQ; continue; }
      if (c === ',' && !inQ) { out.push(cur); cur = ''; continue; }
      cur += c;
    }
    out.push(cur);
    return out.map((s) => s.trim());
  };

  const headers = split(lines[0]).map((h) => h.toLowerCase());
  const required = ['ticker', 'sector', 'quantity', 'avg_cost'];
  for (const col of required) {
    if (!headers.includes(col)) {
      errors.push({ row: 0, field: col, msg: `missing required column "${col}"` });
    }
  }
  if (errors.length > 0) return { rows: [], errors };

  const idx = {
    ticker: headers.indexOf('ticker'),
    sector: headers.indexOf('sector'),
    quantity: headers.indexOf('quantity'),
    avg_cost: headers.indexOf('avg_cost'),
    // Optional columns; -1 if absent.
    strategy: headers.indexOf('strategy'),
    // status governs the SHARES state. Options remain governed by the
    // platform (close trades). Accept "open" / "closed" (with aliases).
    status: headers.indexOf('status'),
  };

  const rows: PositionInput[] = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = split(lines[i]);
    const rowNum = i + 1;
    const ticker = (cols[idx.ticker] ?? '').toUpperCase();
    const sector = cols[idx.sector] ?? '';
    const qty = parseFloat(cols[idx.quantity] ?? '');
    const avg = parseFloat(cols[idx.avg_cost] ?? '');
    const stratRaw = idx.strategy >= 0 ? (cols[idx.strategy] ?? '').trim().toLowerCase() : '';
    const strategy = stratRaw ? STRATEGY_ALIASES[stratRaw] : undefined;
    const statusRaw = idx.status >= 0 ? (cols[idx.status] ?? '').trim().toLowerCase() : '';
    // Map common spellings → canonical 'open' | 'closed'.
    let status: 'open' | 'closed' | undefined;
    if (statusRaw === 'open' || statusRaw === 'o' || statusRaw === '') status = statusRaw === '' ? undefined : 'open';
    else if (statusRaw === 'close' || statusRaw === 'closed' || statusRaw === 'c') status = 'closed';

    if (!ticker || !/^[A-Z0-9.\-]+$/.test(ticker)) {
      errors.push({ row: rowNum, field: 'ticker', msg: `invalid ticker "${cols[idx.ticker]}"` });
    }
    if (!VALID_SECTORS.has(sector)) {
      errors.push({ row: rowNum, field: 'sector', msg: `sector "${sector}" not allowed` });
    }
    if (isNaN(qty) || qty <= 0) {
      errors.push({ row: rowNum, field: 'quantity', msg: `must be positive number, got "${cols[idx.quantity]}"` });
    }
    if (isNaN(avg) || avg < 0) {
      errors.push({ row: rowNum, field: 'avg_cost', msg: `must be non-negative, got "${cols[idx.avg_cost]}"` });
    }
    if (idx.strategy >= 0 && stratRaw && !strategy) {
      errors.push({
        row: rowNum,
        field: 'strategy',
        msg: `strategy "${stratRaw}" must be one of income / invest / yield (blank = unassigned)`,
      });
    }
    if (idx.status >= 0 && statusRaw && status == null) {
      errors.push({
        row: rowNum,
        field: 'status',
        msg: `status "${statusRaw}" must be open / closed (blank = open)`,
      });
    }
    if (
      ticker &&
      VALID_SECTORS.has(sector) &&
      !isNaN(qty) && qty > 0 &&
      !isNaN(avg) && avg >= 0 &&
      (!stratRaw || !!strategy) &&
      (!statusRaw || status != null)
    ) {
      rows.push({ ticker, sector, quantity: qty, avg_cost: avg, strategy, status });
    }
  }
  return { rows, errors };
}

export function CsvUploadModal({ open, onClose, onConfirm }: Props) {
  const [stage, setStage] = useState<Stage>('pick');
  const [filename, setFilename] = useState('');
  const [parsed, setParsed] = useState<ParseResult>({ rows: [], errors: [] });
  const inputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!open) {
      setStage('pick');
      setFilename('');
      setParsed({ rows: [], errors: [] });
    }
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && stage !== 'saving') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, stage, onClose]);

  if (!open) return null;

  const handleFile = async (file: File | undefined) => {
    if (!file) return;
    setFilename(file.name);
    setStage('validating');
    const text = await file.text();
    const result = parseCsv(text);
    setParsed(result);
    setStage(result.errors.length === 0 ? 'preview' : 'error');
  };

  const triggerPick = () => inputRef.current?.click();

  const handleConfirm = async () => {
    setStage('saving');
    try {
      await onConfirm(parsed.rows);
      toast.success(`Replaced ${parsed.rows.length} positions.`);
      onClose();
    } catch (e) {
      toast.error(`Import failed: ${(e as Error).message}`);
      setStage('error');
      setParsed({
        rows: [],
        errors: [{ row: 0, field: '', msg: (e as Error).message }],
      });
    }
  };

  return (
    <div
      className="np-app"
      style={{ position: 'fixed', inset: 0, zIndex: 100 }}
      onClick={() => stage !== 'saving' && onClose()}
    >
      <div className="np-modal-back" onClick={(e) => e.stopPropagation()}>
        <div className="np-modal" onClick={(e) => e.stopPropagation()}>
          <div className="np-modal-hd">
            <div>
              <div className="np-modal-title">Upload positions</div>
              <div className="np-modal-sub">
                CSV columns: ticker, sector, quantity, avg_cost
                {' · optional: strategy (income / invest / yield), status (open / closed)'}
              </div>
            </div>
            <button
              className="np-btn ghost"
              onClick={onClose}
              disabled={stage === 'saving'}
              aria-label="Close"
            >
              ✕ Close
            </button>
          </div>

          <input
            ref={inputRef}
            type="file"
            accept=".csv,text/csv"
            style={{ display: 'none' }}
            onChange={(e) => handleFile(e.target.files?.[0])}
          />

          {stage === 'pick' && (
            <div>
              <div
                className="np-drop"
                onDragOver={(e) => {
                  e.preventDefault();
                  e.currentTarget.classList.add('over');
                }}
                onDragLeave={(e) => e.currentTarget.classList.remove('over')}
                onDrop={(e) => {
                  e.preventDefault();
                  e.currentTarget.classList.remove('over');
                  handleFile(e.dataTransfer.files[0]);
                }}
              >
                <div className="hd">Pick a .csv file</div>
                <div className="sub">Full overwrite of current positions</div>
                <button className="np-btn neon" onClick={triggerPick}>
                  ↑ Choose file
                </button>
              </div>
              <pre
                style={{
                  marginTop: 18,
                  padding: 12,
                  fontSize: 11,
                  fontFamily: 'var(--navi-font-mono)',
                  color: 'var(--navi-fg3)',
                  background: 'rgba(15,51,51,.5)',
                  borderRadius: 6,
                  margin: '18px 0 0 0',
                }}
              >{`ticker,sector,quantity,avg_cost,strategy,status
AAPL,Technology,100,150.25,income,open
CCJ,Energy,500,42.10,invest,open
JEPI,Financials,300,55.40,yield,open
NKE,Consumer Discretionary,200,90.00,invest,closed`}</pre>
            </div>
          )}

          {stage === 'validating' && (
            <div
              style={{
                padding: '60px 0',
                textAlign: 'center',
                color: 'var(--navi-fg2)',
              }}
            >
              Parsing {filename}…
            </div>
          )}

          {stage === 'error' && (
            <div style={{ overflowY: 'auto', flex: 1 }}>
              <div className="np-modal-error">
                <div className="hd">
                  ⚠ {parsed.errors.length} validation issue
                  {parsed.errors.length === 1 ? '' : 's'}
                </div>
                <div className="sub">file: {filename || '(no file)'}</div>
              </div>
              <div className="np-error-list">
                {parsed.errors.slice(0, 60).map((e, i) => (
                  <div key={i} className="row">
                    <span className="r">row {e.row}</span>
                    <span className="f">{e.field}</span>
                    <span className="m">{e.msg}</span>
                  </div>
                ))}
                {parsed.errors.length > 60 && (
                  <div style={{ padding: 8, color: 'var(--navi-fg3)' }}>
                    … {parsed.errors.length - 60} more
                  </div>
                )}
              </div>
              <div
                style={{
                  marginTop: 16,
                  display: 'flex',
                  justifyContent: 'flex-end',
                  gap: 8,
                }}
              >
                <button className="np-btn ghost" onClick={onClose}>
                  Cancel
                </button>
                <button className="np-btn tinted" onClick={triggerPick}>
                  ↑ Different file
                </button>
              </div>
            </div>
          )}

          {stage === 'preview' && (
            <div style={{ overflowY: 'auto', flex: 1 }}>
              <div
                style={{
                  marginBottom: 14,
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'baseline',
                }}
              >
                <div>
                  <div
                    style={{
                      color: 'var(--navi-neon)',
                      fontWeight: 500,
                      fontSize: 14,
                    }}
                  >
                    ✓ {parsed.rows.length} rows ready
                  </div>
                  <div className="np-modal-sub">
                    file: {filename} · will replace all current positions
                  </div>
                </div>
                <span className="np-pill">
                  <span className="dot" />
                  preview
                </span>
              </div>
              <div
                style={{
                  maxHeight: 320,
                  overflowY: 'auto',
                  background: 'rgba(15,51,51,.5)',
                  borderRadius: 6,
                }}
              >
                <table className="np-table" style={{ fontSize: 12 }}>
                  <thead>
                    <tr>
                      <th>Ticker</th>
                      <th>Sector</th>
                      <th>Qty</th>
                      <th>Avg cost</th>
                      <th>Strategy</th>
                    </tr>
                  </thead>
                  <tbody>
                    {parsed.rows.slice(0, 80).map((r, i) => (
                      <tr key={i}>
                        <td className="ticker">{r.ticker}</td>
                        <td className="sector-cell">{r.sector}</td>
                        <td className="num">{fmtQty(r.quantity)}</td>
                        <td className="num">{fmtUSD2(r.avg_cost)}</td>
                        <td className="sector-cell">
                          {r.strategy ?? <span style={{ color: 'var(--navi-fg4)' }}>—</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {parsed.rows.length > 80 && (
                <div
                  style={{
                    marginTop: 8,
                    fontSize: 11,
                    color: 'var(--navi-fg3)',
                  }}
                >
                  Showing first 80 of {parsed.rows.length} rows
                </div>
              )}
              <div
                style={{
                  marginTop: 16,
                  display: 'flex',
                  justifyContent: 'flex-end',
                  gap: 8,
                }}
              >
                <button className="np-btn ghost" onClick={onClose}>
                  Cancel
                </button>
                <button className="np-btn tinted" onClick={triggerPick}>
                  ↑ Different file
                </button>
                <button className="np-btn neon" onClick={handleConfirm}>
                  ✓ Replace positions
                </button>
              </div>
            </div>
          )}

          {stage === 'saving' && (
            <div
              style={{
                padding: 32,
                textAlign: 'center',
                color: 'var(--navi-fg2)',
                fontSize: 13,
              }}
            >
              Importing {parsed.rows.length} positions…
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
