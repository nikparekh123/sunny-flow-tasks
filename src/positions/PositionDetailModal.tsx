import { useEffect, useMemo, useState } from 'react';
import {
  fmtUSD,
  fmtUSD2,
  fmtQty,
  type ExpenseEntry,
  type GainEntry,
  type GainSource,
  type PositionComputed,
  type PutProtectionRow,
} from './types';

/**
 * Position detail modal — Variant B (Sidecar) per design_handoff_position_popup.
 *
 * Single unified modal. Internal Gain ↔ Expense tabs let the user switch
 * ledgers without closing. Source segmented control progressively reveals
 * the right field set (stock vs option). Option fields auto-compute the
 * total via contracts × 100 × premium. A live sidecar rail on the right
 * mirrors the entry as it's being filled in.
 *
 * Inline ledger history is NOT shown here — users get the full timeline
 * via the page-level Gains / Expenses tabs (the "View full history →"
 * link in the rail switches the page-level view).
 */

const SOURCE_META: Record<GainSource, { label: string; short: string }> = {
  stock: { label: 'Stock', short: 'S' },
  call:  { label: 'Call',  short: 'C' },
  put:   { label: 'Put',   short: 'P' },
};

type Bucket = 'income' | 'invest' | 'yield';
const BUCKET_LABEL: Record<Bucket, string> = {
  income: 'Income',
  invest: 'Investment',
  yield: 'Yield',
};

const todayIso = () => new Date().toISOString().slice(0, 10);

interface Props {
  position: PositionComputed;
  entries: GainEntry[];
  expenseEntries: ExpenseEntry[];
  putProtection: PutProtectionRow | undefined;
  bucket?: Bucket;
  /** Which tab opens first. Defaults to 'gain'. */
  initialTab?: 'gain' | 'expense';
  onClose: () => void;
  onAddGain: (p: { ticker: string; gain_date: string; source: GainSource; amount: number; note?: string }) => void;
  onDeleteGain: (id: string) => void;
  onAddExpense: (p: { ticker: string; expense_date: string; source: GainSource; amount: number; note?: string }) => void;
  onDeleteExpense: (id: string) => void;
  onSetPutProtection: (p: { ticker: string; total_cost: number; expiry: string; purchase_date?: string; contracts?: number | null; strike?: number | null }) => void;
  onClearPutProtection: (ticker: string) => void;
  onSetStatus: (p: { ticker: string; status: 'open' | 'closed' }) => void;
  onSetEarningsDate: (p: { ticker: string; earnings_date: string | null }) => void;
  /** Open the matching page-level tab and close the modal. */
  onViewHistory?: (which: 'gain' | 'expense') => void;
}

// Tab state lives in the modal; source + entry form state lives below.
type Tab = 'gain' | 'expense';
type Source = GainSource;

interface EntryForm {
  // Option fields (call / put)
  strike: string;
  contracts: string;
  expiry: string;
  premium: string;
  // Stock fields
  amount: string;
  shares: string;
  // Common
  date: string;
  note: string;
}

const blankEntry = (): EntryForm => ({
  strike: '',
  contracts: '',
  expiry: '',
  premium: '',
  amount: '',
  shares: '',
  date: todayIso(),
  note: '',
});

export function PositionDetailModal({
  position,
  entries,
  expenseEntries,
  putProtection,
  bucket,
  initialTab = 'gain',
  onClose,
  onAddGain,
  onDeleteGain: _onDeleteGain,
  onAddExpense,
  onDeleteExpense: _onDeleteExpense,
  onSetPutProtection,
  onClearPutProtection: _onClearPutProtection,
  onSetStatus,
  onSetEarningsDate: _onSetEarningsDate,
  onViewHistory,
}: Props) {
  // Silence unused-callback warnings — delete/clear are still wired in
  // through the page-level views, not the modal.
  void _onDeleteGain; void _onDeleteExpense; void _onClearPutProtection; void _onSetEarningsDate;

  const [tab, setTab] = useState<Tab>(initialTab);
  const [source, setSource] = useState<Source>('call');
  const [entry, setEntry] = useState<EntryForm>(blankEntry());

  const set = <K extends keyof EntryForm>(k: K, v: EntryForm[K]) =>
    setEntry((prev) => ({ ...prev, [k]: v }));

  // Close on Escape, lock body scroll while the modal is open.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [onClose]);

  const isExp = tab === 'expense';
  const netCls = isExp ? 'neg' : 'pos';
  const isClosed = position.status === 'closed';

  // Aggregates for the rail's net big-number — week + YTD.
  const summary = useMemo(() => {
    const today = new Date(); today.setUTCHours(0, 0, 0, 0);
    const weekStart = new Date(today.getTime() - 7 * 86400000);
    const yearStart = new Date(Date.UTC(today.getUTCFullYear(), 0, 1));
    const fold = (rows: Array<{ date: string; amount: number }>) => {
      let netWk = 0, netYtd = 0, count = 0;
      for (const r of rows) {
        const d = new Date(r.date + 'T00:00:00Z');
        if (d >= yearStart) netYtd += r.amount;
        if (d >= weekStart) netWk += r.amount;
        count += 1;
      }
      return { netWk, netYtd, count };
    };
    return {
      gain: fold(entries.map((e) => ({ date: e.gain_date, amount: e.amount }))),
      // Expense rows store magnitudes; flip sign for the rail.
      expense: fold(expenseEntries.map((e) => ({ date: e.expense_date, amount: -Math.abs(e.amount) }))),
    };
  }, [entries, expenseEntries]);

  const st = summary[tab];

  // Total auto-calc: contracts × 100 × premium. Sign controlled by tab.
  const optionTotal =
    (parseFloat(entry.contracts) || 0) * 100 * (parseFloat(entry.premium) || 0);
  const signedTotal = (isExp ? -1 : 1) * optionTotal;

  // Live preview row in the rail. For stock, sign is just tab.
  const previewAmt =
    source === 'stock'
      ? (parseFloat(entry.amount) || 0) * (isExp ? -1 : 1)
      : signedTotal;
  const previewLabel =
    source === 'call' ? (isExp ? 'call expense' : 'calls sold')
    : source === 'put' ? (isExp ? 'put protection' : 'puts sold')
    : isExp ? 'stock expense' : 'stock gain';

  const canSubmit = (() => {
    if (!entry.date) return false;
    if (source === 'stock') return !!entry.amount && parseFloat(entry.amount) > 0;
    return !!entry.strike && !!entry.contracts && !!entry.expiry && !!entry.premium
      && parseFloat(entry.contracts) > 0 && parseFloat(entry.premium) > 0;
  })();

  const submit = () => {
    if (!canSubmit) return;
    const total = source === 'stock' ? parseFloat(entry.amount) : optionTotal;
    if (!total || isNaN(total)) return;
    const noteLine = source === 'stock'
      ? entry.note
      : [
          entry.note,
          `${entry.contracts}× $${entry.strike} ${source} exp ${entry.expiry} @ $${entry.premium}/sh`,
        ].filter(Boolean).join(' · ');
    if (isExp) {
      // Expenses store magnitudes; total is always positive.
      onAddExpense({
        ticker: position.ticker,
        expense_date: entry.date,
        source,
        amount: Math.abs(total),
        note: noteLine || undefined,
      });
      // For put expenses with structured data, also upsert put_protection so
      // the strategy cards' MTM works.
      if (source === 'put') {
        onSetPutProtection({
          ticker: position.ticker,
          total_cost: Math.abs(total),
          expiry: entry.expiry,
          purchase_date: entry.date,
          contracts: parseInt(entry.contracts, 10) || null,
          strike: parseFloat(entry.strike) || null,
        });
      }
    } else {
      onAddGain({
        ticker: position.ticker,
        gain_date: entry.date,
        source,
        amount: total,
        note: noteLine || undefined,
      });
    }
    setEntry(blankEntry());
    setSource(source); // reset to current source for next entry
  };

  return (
    <div className="pp-stage" onClick={onClose}>
      <div className="pp-popup" role="dialog" aria-labelledby="pp-ticker" onClick={(e) => e.stopPropagation()}>
        {/* HEAD */}
        <div className="pp-popup-head">
          <div className="pp-head-info">
            <h2 className="pp-popup-ticker" id="pp-ticker">{position.ticker}</h2>
            <div className="pp-popup-sub">
              {bucket && <span>{BUCKET_LABEL[bucket]}</span>}
              {bucket && <span className="dot">·</span>}
              <span>{position.sector}</span>
              {!isClosed && (
                <>
                  <span className="dot">·</span>
                  <span>{fmtQty(position.quantity)} sh @ {fmtUSD2(position.avg_cost)}</span>
                </>
              )}
              {isClosed && <span className="pp-pill-closed">closed</span>}
            </div>
          </div>
          <div className="pp-popup-head-actions">
            <button className="pp-icon-btn" onClick={onClose} aria-label="Close">✕ Close</button>
          </div>
        </div>

        {/* TABS */}
        <div className="pp-tab-row">
          <button className={'pp-tab' + (tab === 'gain' ? ' on' : '')} onClick={() => setTab('gain')}>
            Gain<span className="pp-tab-count">{entries.length}</span>
          </button>
          <button className={'pp-tab' + (tab === 'expense' ? ' on' : '')} onClick={() => setTab('expense')}>
            Expense<span className="pp-tab-count">{expenseEntries.length}</span>
          </button>
        </div>

        {/* SIDECAR */}
        <div className="pp-sidecar">
          {/* LEFT — form */}
          <div className="pp-form">
            <div className="pp-field">
              <div className="pp-field-label">Source</div>
              <SourceSeg value={source} onChange={setSource} />
            </div>

            {source === 'stock' ? (
              <StockFields entry={entry} set={set} />
            ) : (
              <OptionFields source={source} entry={entry} set={set} tab={tab} signedTotal={signedTotal} optionTotal={optionTotal} />
            )}

            <div className="pp-form-grid cols-2">
              <div className="pp-field">
                <div className="pp-field-label">Date</div>
                <input
                  className="pp-input mono"
                  type="date"
                  value={entry.date}
                  onChange={(e) => set('date', e.target.value)}
                />
              </div>
              <div className="pp-field">
                <div className="pp-field-label">Note (optional)</div>
                <input
                  className="pp-input"
                  value={entry.note}
                  onChange={(e) => set('note', e.target.value)}
                  placeholder="strike, ex-div, source, etc."
                />
              </div>
            </div>
          </div>

          {/* RIGHT — rail */}
          <aside className="pp-rail">
            <div className="pp-rail-section">
              <div className="pp-rail-lbl">Position</div>
              <div className="pp-rail-row">
                <span className="k">Shares</span>
                <span className="v">{fmtQty(position.quantity)}</span>
              </div>
              <div className="pp-rail-row">
                <span className="k">Avg basis</span>
                <span className="v">{fmtUSD2(position.avg_cost)}</span>
              </div>
              <div className="pp-rail-row">
                <span className="k">Mkt value</span>
                <span className="v">{fmtUSD(position.market_value)}</span>
              </div>
            </div>

            <div className="pp-rail-divider" />

            <div className="pp-rail-section">
              <div className="pp-rail-lbl">Net · {isExp ? 'expense' : 'gain'}</div>
              <div className={'pp-rail-bignum ' + netCls}>{fmtSigned(st.netWk)}</div>
              <div className="pp-rail-sub">
                {st.count} {st.count === 1 ? 'entry' : 'entries'} · this wk · YTD {fmtSigned(st.netYtd)}
              </div>
            </div>

            <div className="pp-rail-divider" />

            <div className="pp-rail-section">
              <div className="pp-rail-lbl">Entry preview</div>
              <div className={'pp-preview-row ' + (previewAmt < 0 ? 'neg' : previewAmt > 0 ? 'pos' : '')}>
                <span className={'pp-mini-glyph ' + (source === 'stock' ? '' : 'neon')}>
                  {SOURCE_META[source].short}
                </span>
                <span className="pp-preview-date">{entry.date}</span>
                {previewAmt !== 0 ? (
                  <span className={'pp-preview-amt ' + (previewAmt < 0 ? 'neg' : 'pos')}>
                    {fmtSigned(previewAmt)}
                  </span>
                ) : (
                  <span className="pp-preview-empty">— fill amount —</span>
                )}
                <span className="pp-preview-meta">{previewLabel}</span>
              </div>
            </div>

            <div className="pp-rail-divider" />

            <div className="pp-rail-links">
              {onViewHistory && (
                <button className="pp-rail-link" onClick={() => onViewHistory(tab)}>
                  View full history →
                </button>
              )}
              <button
                className="pp-rail-link danger"
                onClick={() => onSetStatus({ ticker: position.ticker, status: isClosed ? 'open' : 'closed' })}
              >
                {isClosed ? '↻ Reopen position' : '✕ Mark position closed'}
              </button>
            </div>
          </aside>
        </div>

        {/* FOOT */}
        <div className="pp-popup-foot">
          <div />
          <div className="pp-popup-foot-end">
            <button className="pp-btn pp-btn-text" onClick={onClose}>Cancel</button>
            <button className="pp-btn pp-btn-neon" onClick={submit} disabled={!canSubmit}>
              ✓ Add {isExp ? 'expense' : 'gain'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ───────────────────────────────────────────── helpers + sub-components

function fmtSigned(n: number): string {
  if (!n) return '$0';
  const sign = n < 0 ? '−' : '';
  return sign + '$' + Math.abs(n).toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function SourceSeg({ value, onChange }: { value: Source; onChange: (s: Source) => void }) {
  const opts: Array<{ k: Source; label: string; g: string }> = [
    { k: 'stock', label: 'Stock', g: 'S' },
    { k: 'call',  label: 'Call',  g: 'C' },
    { k: 'put',   label: 'Put',   g: 'P' },
  ];
  return (
    <div className="pp-source-seg" role="tablist">
      {opts.map((o) => (
        <button
          key={o.k}
          type="button"
          className={'pp-source-opt' + (value === o.k ? ' on' : '')}
          onClick={() => onChange(o.k)}
        >
          <span className="pp-glyph-tile">{o.g}</span>
          <span>{o.label}</span>
        </button>
      ))}
    </div>
  );
}

function OptionFields({
  source, entry, set, tab, signedTotal, optionTotal,
}: {
  source: Source;
  entry: EntryForm;
  set: <K extends keyof EntryForm>(k: K, v: EntryForm[K]) => void;
  tab: Tab;
  signedTotal: number;
  optionTotal: number;
}) {
  const sign = tab === 'expense' ? 'neg' : 'pos';
  return (
    <>
      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Strike</div>
          <MoneyInput value={entry.strike} onChange={(v) => set('strike', v)} placeholder="0.00" />
        </div>
        <div className="pp-field">
          <div className="pp-field-label">Contracts</div>
          <input
            className="pp-input mono"
            type="number"
            min="1"
            step="1"
            value={entry.contracts}
            onChange={(e) => set('contracts', e.target.value)}
            placeholder="0"
          />
        </div>
      </div>
      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Expiry</div>
          <input
            className="pp-input mono"
            type="date"
            value={entry.expiry}
            onChange={(e) => set('expiry', e.target.value)}
          />
        </div>
        <div className="pp-field">
          <div className="pp-field-label">
            {source === 'put' ? 'Premium paid / sh' : 'Premium / sh'}
          </div>
          <MoneyInput value={entry.premium} onChange={(v) => set('premium', v)} placeholder="0.00" />
        </div>
      </div>
      <div className="pp-field">
        <div className="pp-field-label">Total</div>
        <div className={'pp-calc-tile ' + sign}>
          <span className="num">{optionTotal > 0 ? fmtSigned(signedTotal) : '—'}</span>
          <span className="formula">contracts × 100 × premium</span>
        </div>
      </div>
    </>
  );
}

function StockFields({
  entry, set,
}: {
  entry: EntryForm;
  set: <K extends keyof EntryForm>(k: K, v: EntryForm[K]) => void;
}) {
  return (
    <div className="pp-form-grid cols-2">
      <div className="pp-field">
        <div className="pp-field-label">Amount</div>
        <MoneyInput value={entry.amount} onChange={(v) => set('amount', v)} placeholder="0.00" />
      </div>
      <div className="pp-field">
        <div className="pp-field-label">Shares (optional)</div>
        <input
          className="pp-input mono"
          type="number"
          value={entry.shares}
          onChange={(e) => set('shares', e.target.value)}
          placeholder="0"
        />
        <div className="pp-field-hint">leave blank for ad-hoc dividends</div>
      </div>
    </div>
  );
}

function MoneyInput({
  value, onChange, placeholder,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="pp-input-prefix">
      <span className="pp-pfx">$</span>
      <input
        className="pp-input mono"
        type="number"
        step="0.01"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
      />
    </div>
  );
}

// Keep these imports referenced so TS doesn't flag the file when types
// are imported elsewhere; PutProtectionRow is part of Props above.
void {} as unknown as PutProtectionRow;
