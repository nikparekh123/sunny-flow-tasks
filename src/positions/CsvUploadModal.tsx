import { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import { toast } from 'sonner';
import { SECTORS, type Sector, fmtQty, fmtUSD2 } from './types';
import type { PositionInput } from './usePositions';

interface Props {
  open: boolean;
  onClose: () => void;
  onConfirm: (rows: PositionInput[]) => Promise<void>;
}

type Stage = 'pick' | 'preview' | 'error' | 'saving';

const VALID_SECTORS = new Set<string>(SECTORS);

interface ParseResult {
  rows: PositionInput[];
  errors: string[];
}

function parseCsv(text: string): ParseResult {
  const lines = text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  if (lines.length === 0) return { rows: [], errors: ['Empty file.'] };

  const header = lines[0].toLowerCase().split(',').map((s) => s.trim());
  const required = ['ticker', 'sector', 'quantity', 'avg_cost'];
  for (const k of required) {
    if (!header.includes(k)) {
      return {
        rows: [],
        errors: [
          `Missing required column "${k}". Header must be: ${required.join(', ')}`,
        ],
      };
    }
  }
  const idx = {
    ticker: header.indexOf('ticker'),
    sector: header.indexOf('sector'),
    quantity: header.indexOf('quantity'),
    avg_cost: header.indexOf('avg_cost'),
  };

  const rows: PositionInput[] = [];
  const errors: string[] = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = lines[i].split(',').map((s) => s.trim());
    if (cols.length < 4) {
      errors.push(`Row ${i + 1}: not enough columns.`);
      continue;
    }
    const ticker = cols[idx.ticker].toUpperCase();
    const sector = cols[idx.sector];
    const quantity = Number(cols[idx.quantity]);
    const avg_cost = Number(cols[idx.avg_cost]);
    if (!ticker) {
      errors.push(`Row ${i + 1}: missing ticker.`);
      continue;
    }
    if (isNaN(quantity) || quantity <= 0) {
      errors.push(`Row ${i + 1} (${ticker}): bad quantity "${cols[idx.quantity]}".`);
      continue;
    }
    if (isNaN(avg_cost) || avg_cost < 0) {
      errors.push(`Row ${i + 1} (${ticker}): bad avg_cost "${cols[idx.avg_cost]}".`);
      continue;
    }
    if (!VALID_SECTORS.has(sector)) {
      errors.push(
        `Row ${i + 1} (${ticker}): unknown sector "${sector}", will be filed under "Other".`,
      );
    }
    rows.push({ ticker, sector: VALID_SECTORS.has(sector) ? sector : 'Other', quantity, avg_cost });
  }
  return { rows, errors };
}

export function CsvUploadModal({ open, onClose, onConfirm }: Props) {
  const [stage, setStage] = useState<Stage>('pick');
  const [text, setText] = useState('');
  const [parsed, setParsed] = useState<ParseResult>({ rows: [], errors: [] });

  // Reset on close
  useEffect(() => {
    if (!open) {
      setStage('pick');
      setText('');
      setParsed({ rows: [], errors: [] });
    }
  }, [open]);

  // Esc to close
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && stage !== 'saving') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, stage, onClose]);

  if (!open) return null;

  const validate = () => {
    const result = parseCsv(text);
    setParsed(result);
    if (result.rows.length === 0) {
      setStage('error');
    } else {
      setStage('preview');
    }
  };

  const handleFile = async (file: File) => {
    const txt = await file.text();
    setText(txt);
    const result = parseCsv(txt);
    setParsed(result);
    setStage(result.rows.length === 0 ? 'error' : 'preview');
  };

  const handleConfirm = async () => {
    setStage('saving');
    try {
      await onConfirm(parsed.rows);
      toast.success(`Imported ${parsed.rows.length} positions.`);
      onClose();
    } catch (e) {
      toast.error(`Import failed: ${(e as Error).message}`);
      setStage('error');
      setParsed({ rows: [], errors: [(e as Error).message] });
    }
  };

  const sectorCount = new Set(parsed.rows.map((r) => r.sector)).size;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.6)',
        zIndex: 100,
        display: 'flex',
        alignItems: 'flex-start',
        justifyContent: 'center',
        padding: '8vh 20px 20px',
      }}
      onClick={() => stage !== 'saving' && onClose()}
    >
      <div
        role="dialog"
        aria-label="Upload positions"
        onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%',
          maxWidth: 560,
          background: 'var(--owl-surface)',
          border: '1px solid var(--owl-elevated)',
          padding: 32,
          color: 'var(--owl-text-primary)',
        }}
      >
        <div className="flex items-center justify-between mb-4">
          <h2
            style={{
              fontSize: 20,
              fontWeight: 500,
              letterSpacing: '-0.3px',
            }}
          >
            Upload positions
          </h2>
          <button
            onClick={onClose}
            disabled={stage === 'saving'}
            aria-label="Close"
            style={{
              background: 'transparent',
              border: 'none',
              color: 'var(--owl-text-muted)',
              cursor: stage === 'saving' ? 'not-allowed' : 'pointer',
            }}
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {stage === 'pick' && (
          <PickStage
            text={text}
            onText={setText}
            onFile={handleFile}
            onValidate={validate}
          />
        )}
        {stage === 'preview' && (
          <PreviewStage
            rows={parsed.rows}
            sectorCount={sectorCount}
            warnings={parsed.errors}
            onConfirm={handleConfirm}
            onBack={() => setStage('pick')}
          />
        )}
        {stage === 'error' && (
          <ErrorStage
            errors={parsed.errors}
            onRetry={() => setStage('pick')}
          />
        )}
        {stage === 'saving' && (
          <div
            style={{
              padding: 32,
              textAlign: 'center',
              color: 'var(--owl-text-muted)',
              fontSize: 13,
            }}
          >
            Importing {parsed.rows.length} positions…
          </div>
        )}
      </div>
    </div>
  );
}

function PickStage({
  text,
  onText,
  onFile,
  onValidate,
}: {
  text: string;
  onText: (t: string) => void;
  onFile: (f: File) => void;
  onValidate: () => void;
}) {
  const [dragOver, setDragOver] = useState(false);
  return (
    <div className="flex flex-col gap-4">
      <p style={{ fontSize: 12, color: 'var(--owl-text-muted)', lineHeight: 1.5 }}>
        CSV format: <code>ticker,sector,quantity,avg_cost</code> (header row required).
        This <b>replaces</b> all existing positions.
      </p>

      <label
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragOver(false);
          const f = e.dataTransfer.files[0];
          if (f) onFile(f);
        }}
        style={{
          border: dragOver
            ? '1px solid var(--owl-neon)'
            : '1px dashed var(--owl-elevated)',
          padding: '24px 16px',
          textAlign: 'center',
          cursor: 'pointer',
          background: dragOver ? 'var(--owl-tint-neon)' : 'transparent',
          fontSize: 13,
          color: 'var(--owl-text-secondary)',
        }}
      >
        Drop a CSV here, or click to choose a file
        <input
          type="file"
          accept=".csv,text/csv"
          style={{ display: 'none' }}
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) onFile(f);
          }}
        />
      </label>

      <div
        style={{
          fontSize: 10,
          fontWeight: 600,
          letterSpacing: '1.5px',
          textTransform: 'uppercase',
          color: 'var(--owl-text-label)',
        }}
      >
        Or paste below
      </div>
      <textarea
        value={text}
        onChange={(e) => onText(e.target.value)}
        placeholder="ticker,sector,quantity,avg_cost&#10;AAPL,Technology,100,150.00&#10;MSFT,Technology,50,300.00"
        rows={6}
        style={{
          background: 'rgba(15,51,51,0.6)',
          border: 'none',
          color: 'var(--owl-text-primary)',
          fontFamily: 'var(--owl-font-mono)',
          fontSize: 12,
          padding: 12,
          outline: 'none',
          resize: 'vertical',
          width: '100%',
        }}
      />
      <div className="flex justify-end gap-2">
        <button
          onClick={onValidate}
          disabled={!text.trim()}
          style={{
            background: 'var(--owl-tint-neon)',
            color: 'var(--owl-neon)',
            border: 'none',
            padding: '8px 14px',
            fontSize: 12,
            fontWeight: 500,
            cursor: text.trim() ? 'pointer' : 'not-allowed',
            opacity: text.trim() ? 1 : 0.5,
          }}
        >
          Validate
        </button>
      </div>
    </div>
  );
}

function PreviewStage({
  rows,
  sectorCount,
  warnings,
  onConfirm,
  onBack,
}: {
  rows: PositionInput[];
  sectorCount: number;
  warnings: string[];
  onConfirm: () => void;
  onBack: () => void;
}) {
  return (
    <div className="flex flex-col gap-4">
      <div
        style={{
          padding: 12,
          background: 'var(--owl-tint-positive)',
          color: 'var(--owl-positive)',
          fontSize: 13,
        }}
      >
        ✓ Parsed {rows.length} positions across {sectorCount} sectors. Ready to import.
      </div>

      <div style={{ maxHeight: 280, overflowY: 'auto' }}>
        <table style={{ width: '100%', fontSize: 12, borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <Th>Ticker</Th>
              <Th>Sector</Th>
              <Th align="right">Qty</Th>
              <Th align="right">Avg cost</Th>
            </tr>
          </thead>
          <tbody>
            {rows.slice(0, 50).map((r, i) => (
              <tr key={i}>
                <Td>{r.ticker}</Td>
                <Td>
                  <span style={{ color: 'var(--owl-text-muted)' }}>{r.sector}</span>
                </Td>
                <Td align="right">{fmtQty(r.quantity)}</Td>
                <Td align="right">{fmtUSD2(r.avg_cost)}</Td>
              </tr>
            ))}
            {rows.length > 50 && (
              <tr>
                <td
                  colSpan={4}
                  style={{
                    padding: 8,
                    textAlign: 'center',
                    fontSize: 11,
                    color: 'var(--owl-text-muted)',
                  }}
                >
                  + {rows.length - 50} more rows
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {warnings.length > 0 && (
        <div
          style={{
            padding: 12,
            background: 'var(--owl-tint-warning)',
            color: 'var(--owl-warning)',
            fontSize: 12,
            maxHeight: 100,
            overflowY: 'auto',
          }}
        >
          <div style={{ fontWeight: 600, marginBottom: 4 }}>
            {warnings.length} warning{warnings.length === 1 ? '' : 's'}:
          </div>
          {warnings.map((w, i) => (
            <div key={i}>• {w}</div>
          ))}
        </div>
      )}

      <div className="flex justify-end gap-2">
        <button
          onClick={onBack}
          style={{
            background: 'transparent',
            color: 'var(--owl-text-muted)',
            border: 'none',
            padding: '8px 14px',
            fontSize: 12,
            cursor: 'pointer',
          }}
        >
          Back
        </button>
        <button
          onClick={onConfirm}
          style={{
            background: 'var(--owl-tint-neon)',
            color: 'var(--owl-neon)',
            border: 'none',
            padding: '8px 14px',
            fontSize: 12,
            fontWeight: 500,
            cursor: 'pointer',
          }}
        >
          Confirm import
        </button>
      </div>
    </div>
  );
}

function ErrorStage({
  errors,
  onRetry,
}: {
  errors: string[];
  onRetry: () => void;
}) {
  return (
    <div className="flex flex-col gap-4">
      <div
        style={{
          padding: 12,
          background: 'var(--owl-tint-negative)',
          color: 'var(--owl-negative)',
          fontSize: 13,
          fontWeight: 500,
        }}
      >
        ✗ Import failed
      </div>
      <ul
        style={{
          fontSize: 12,
          color: 'var(--owl-text-secondary)',
          lineHeight: 1.6,
          paddingLeft: 16,
        }}
      >
        {errors.map((e, i) => (
          <li key={i}>{e}</li>
        ))}
      </ul>
      <div className="flex justify-end">
        <button
          onClick={onRetry}
          style={{
            background: 'var(--owl-tint-neon)',
            color: 'var(--owl-neon)',
            border: 'none',
            padding: '8px 14px',
            fontSize: 12,
            fontWeight: 500,
            cursor: 'pointer',
          }}
        >
          Retry
        </button>
      </div>
    </div>
  );
}

function Th({
  children,
  align,
}: {
  children: React.ReactNode;
  align?: 'left' | 'right';
}) {
  return (
    <th
      style={{
        textAlign: align ?? 'left',
        padding: '8px',
        fontSize: 9,
        fontWeight: 600,
        letterSpacing: '1.2px',
        textTransform: 'uppercase',
        color: 'var(--owl-text-muted)',
        borderBottom: '1px solid var(--owl-elevated)',
      }}
    >
      {children}
    </th>
  );
}
function Td({
  children,
  align,
}: {
  children: React.ReactNode;
  align?: 'left' | 'right';
}) {
  return (
    <td
      style={{
        padding: '6px 8px',
        textAlign: align ?? 'left',
        fontFamily: align === 'right' ? 'var(--owl-font-mono)' : undefined,
        borderBottom: '1px solid var(--owl-line)',
      }}
    >
      {children}
    </td>
  );
}
