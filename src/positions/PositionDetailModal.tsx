import { useEffect, useMemo, useState } from 'react';
import {
  closeRealizedPL,
  fmtUSD,
  fmtUSD2,
  fmtQty,
  type Direction,
  type LiveOption,
  type OptionTrade,
  type OptionType,
  type PositionComputed,
} from './types';

/**
 * Trade logger — Open / Close tabs.
 *
 * Open: enter a new options position (long/short call/put). The total cash
 * impact is computed as contracts × 100 × premium and signed by direction.
 *
 * Close: pick from the position's live opens, enter the close premium and
 * contracts, and the realized P&L is shown live in the rail before save.
 * Closes are linked to the source open via closes_trade_id so partial
 * closes work naturally.
 */

type Bucket = 'income' | 'invest' | 'yield';
const BUCKET_LABEL: Record<Bucket, string> = {
  income: 'Income',
  invest: 'Investment',
  yield: 'Yield',
};

const todayIso = () => new Date().toISOString().slice(0, 10);

interface Props {
  position: PositionComputed;
  liveOpens: LiveOption[];
  bucket?: Bucket;
  initialTab?: 'open' | 'close';
  /** Pre-selected live open for the close tab. */
  initialCloseTarget?: string;
  onClose: () => void;
  onAddTrade: (p: {
    ticker: string;
    trade_date: string;
    action: 'open' | 'close';
    option_type: OptionType;
    direction: Direction;
    contracts: number;
    strike: number;
    premium: number;
    expiry: string;
    closes_trade_id?: string | null;
    note?: string | null;
  }) => void;
  onSetStatus: (p: { ticker: string; status: 'open' | 'closed' }) => void;
}

type Tab = 'open' | 'close';

interface OpenForm {
  option_type: OptionType;
  direction: Direction;
  contracts: string;
  strike: string;
  premium: string;
  expiry: string;
  date: string;
  note: string;
}

interface CloseForm {
  target_id: string;       // open trade we're closing against
  contracts: string;
  premium: string;
  date: string;
  note: string;
}

const blankOpen = (): OpenForm => ({
  option_type: 'put',
  direction: 'short',
  contracts: '',
  strike: '',
  premium: '',
  expiry: '',
  date: todayIso(),
  note: '',
});

const blankClose = (targetId: string): CloseForm => ({
  target_id: targetId,
  contracts: '',
  premium: '',
  date: todayIso(),
  note: '',
});

export function PositionDetailModal({
  position,
  liveOpens,
  bucket,
  initialTab = 'open',
  initialCloseTarget,
  onClose,
  onAddTrade,
  onSetStatus,
}: Props) {
  const [tab, setTab] = useState<Tab>(liveOpens.length === 0 ? 'open' : initialTab);
  const [openForm, setOpenForm] = useState<OpenForm>(blankOpen());
  const [closeForm, setCloseForm] = useState<CloseForm>(
    blankClose(initialCloseTarget ?? liveOpens[0]?.open.id ?? ''),
  );

  useEffect(() => {
    // When the live opens list changes (or we mount), make sure the close
    // target is one of them.
    if (liveOpens.length > 0 && !liveOpens.some((l) => l.open.id === closeForm.target_id)) {
      setCloseForm((prev) => ({ ...prev, target_id: liveOpens[0].open.id }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [liveOpens.length]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [onClose]);

  const isClosed = position.status === 'closed';

  // ── Open tab math ──────────────────────────────────────────────
  const openTotal =
    (parseFloat(openForm.contracts) || 0) * 100 * (parseFloat(openForm.premium) || 0);
  const openSignedTotal = openForm.direction === 'short' ? openTotal : -openTotal;
  const canSubmitOpen =
    !!openForm.contracts && !!openForm.strike && !!openForm.premium && !!openForm.expiry &&
    parseFloat(openForm.contracts) > 0 && parseFloat(openForm.strike) > 0 && parseFloat(openForm.premium) >= 0;

  // ── Close tab math ─────────────────────────────────────────────
  const closeTarget = useMemo(
    () => liveOpens.find((l) => l.open.id === closeForm.target_id) ?? null,
    [liveOpens, closeForm.target_id],
  );
  const closeContractsN = parseInt(closeForm.contracts, 10) || 0;
  const closePremiumN = parseFloat(closeForm.premium) || 0;
  const canSubmitClose =
    !!closeTarget &&
    closeContractsN > 0 &&
    closeContractsN <= closeTarget.remaining_contracts &&
    closePremiumN >= 0;
  const closeRealized = closeTarget
    ? closeRealizedPL(
        {
          ...closeTarget.open,
          action: 'close',
          contracts: closeContractsN,
          premium: closePremiumN,
        },
        closeTarget.open,
      )
    : 0;

  const submitOpen = () => {
    if (!canSubmitOpen) return;
    onAddTrade({
      ticker: position.ticker,
      trade_date: openForm.date,
      action: 'open',
      option_type: openForm.option_type,
      direction: openForm.direction,
      contracts: parseInt(openForm.contracts, 10),
      strike: parseFloat(openForm.strike),
      premium: parseFloat(openForm.premium),
      expiry: openForm.expiry,
      note: openForm.note || null,
    });
    setOpenForm(blankOpen());
  };

  const submitClose = () => {
    if (!canSubmitClose || !closeTarget) return;
    onAddTrade({
      ticker: position.ticker,
      trade_date: closeForm.date,
      action: 'close',
      option_type: closeTarget.open.option_type,
      direction: closeTarget.open.direction,
      contracts: closeContractsN,
      strike: closeTarget.open.strike,
      premium: closePremiumN,
      expiry: closeTarget.open.expiry,
      closes_trade_id: closeTarget.open.id,
      note: closeForm.note || null,
    });
    setCloseForm(blankClose(closeForm.target_id));
  };

  return (
    <div className="pp-stage" onClick={onClose}>
      <div className="pp-popup" role="dialog" onClick={(e) => e.stopPropagation()}>
        {/* HEAD */}
        <div className="pp-popup-head">
          <div className="pp-head-info">
            <h2 className="pp-popup-ticker">{position.ticker}</h2>
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
          <button className="pp-icon-btn" onClick={onClose}>✕ Close</button>
        </div>

        {/* TABS */}
        <div className="pp-tab-row">
          <button
            className={'pp-tab' + (tab === 'open' ? ' on' : '')}
            onClick={() => setTab('open')}
          >
            Open<span className="pp-tab-count">{liveOpens.length}</span>
          </button>
          <button
            className={'pp-tab' + (tab === 'close' ? ' on' : '') + (liveOpens.length === 0 ? ' disabled' : '')}
            onClick={() => liveOpens.length > 0 && setTab('close')}
            disabled={liveOpens.length === 0}
            title={liveOpens.length === 0 ? 'No live positions to close' : ''}
          >
            Close
          </button>
        </div>

        {/* SIDECAR */}
        <div className="pp-sidecar">
          <div className="pp-form">
            {tab === 'open' ? (
              <OpenFields form={openForm} setForm={setOpenForm} />
            ) : (
              <CloseFields
                form={closeForm}
                setForm={setCloseForm}
                liveOpens={liveOpens}
                target={closeTarget}
              />
            )}
          </div>

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
              <div className="pp-rail-lbl">Live positions · {liveOpens.length}</div>
              {liveOpens.length === 0 ? (
                <div className="pp-rail-sub">none open</div>
              ) : (
                <div className="pp-rail-livelist">
                  {liveOpens.slice(0, 4).map((lo) => (
                    <div key={lo.open.id} className="pp-rail-live-row">
                      <span className={'pp-mini-glyph ' + (lo.open.direction === 'short' ? 'neg' : 'pos')}>
                        {lo.open.option_type === 'put' ? 'P' : 'C'}
                      </span>
                      <span className="pp-rail-live-meta">
                        {lo.open.direction === 'short' ? '−' : '+'}{lo.remaining_contracts} @ ${lo.open.strike}
                      </span>
                      <span className="pp-rail-live-exp">{lo.open.expiry}</span>
                    </div>
                  ))}
                  {liveOpens.length > 4 && (
                    <div className="pp-rail-sub">+ {liveOpens.length - 4} more</div>
                  )}
                </div>
              )}
            </div>

            <div className="pp-rail-divider" />

            <div className="pp-rail-section">
              <div className="pp-rail-lbl">
                {tab === 'open' ? 'New trade preview' : 'Realized P&L'}
              </div>
              {tab === 'open' ? (
                <>
                  <div className={'pp-rail-bignum ' + (openSignedTotal > 0 ? 'pos' : openSignedTotal < 0 ? 'neg' : '')}>
                    {openSignedTotal === 0
                      ? '—'
                      : openSignedTotal > 0
                        ? fmtUSD(openSignedTotal)
                        : '−' + fmtUSD(Math.abs(openSignedTotal))}
                  </div>
                  <div className="pp-rail-sub">
                    {openForm.direction === 'short' ? 'premium collected' : 'premium paid'}
                  </div>
                </>
              ) : (
                <>
                  <div className={'pp-rail-bignum ' + (closeRealized > 0 ? 'pos' : closeRealized < 0 ? 'neg' : '')}>
                    {closeRealized === 0
                      ? '—'
                      : closeRealized > 0
                        ? fmtUSD(closeRealized)
                        : '−' + fmtUSD(Math.abs(closeRealized))}
                  </div>
                  <div className="pp-rail-sub">
                    {closeTarget ? `vs ${closeTarget.open.direction} open @ $${closeTarget.open.premium}/sh` : 'pick a position'}
                  </div>
                </>
              )}
            </div>
          </aside>
        </div>

        {/* FOOT */}
        <div className="pp-popup-foot">
          <button
            className="pi-link danger"
            onClick={() => onSetStatus({ ticker: position.ticker, status: isClosed ? 'open' : 'closed' })}
          >
            {isClosed ? '↻ Reopen position' : '✕ Mark position closed'}
          </button>
          <div className="pp-popup-foot-end">
            <button className="pp-btn pp-btn-text" onClick={onClose}>Cancel</button>
            {tab === 'open' ? (
              <button className="pp-btn pp-btn-neon" onClick={submitOpen} disabled={!canSubmitOpen}>
                ✓ Open position
              </button>
            ) : (
              <button className="pp-btn pp-btn-neon" onClick={submitClose} disabled={!canSubmitClose}>
                ✓ Close position
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// ───────────────────────── Sub-components

function OpenFields({
  form, setForm,
}: {
  form: OpenForm;
  setForm: (f: OpenForm) => void;
}) {
  const set = <K extends keyof OpenForm>(k: K, v: OpenForm[K]) =>
    setForm({ ...form, [k]: v });

  return (
    <>
      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Option type</div>
          <div className="pp-source-seg">
            {(['call', 'put'] as OptionType[]).map((k) => (
              <button
                key={k}
                type="button"
                className={'pp-source-opt' + (form.option_type === k ? ' on' : '')}
                onClick={() => set('option_type', k)}
              >
                <span className="pp-glyph-tile">{k === 'call' ? 'C' : 'P'}</span>
                <span>{k === 'call' ? 'Call' : 'Put'}</span>
              </button>
            ))}
          </div>
        </div>
        <div className="pp-field">
          <div className="pp-field-label">Direction</div>
          <div className="pp-source-seg">
            <button
              type="button"
              className={'pp-source-opt' + (form.direction === 'short' ? ' on' : '')}
              onClick={() => set('direction', 'short')}
            >
              <span className="pp-glyph-tile">−</span>
              <span>Short</span>
            </button>
            <button
              type="button"
              className={'pp-source-opt' + (form.direction === 'long' ? ' on' : '')}
              onClick={() => set('direction', 'long')}
            >
              <span className="pp-glyph-tile">+</span>
              <span>Long</span>
            </button>
          </div>
        </div>
      </div>

      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Strike</div>
          <MoneyInput value={form.strike} onChange={(v) => set('strike', v)} placeholder="0.00" />
        </div>
        <div className="pp-field">
          <div className="pp-field-label">Contracts</div>
          <input
            className="pp-input mono"
            type="number"
            min="1"
            step="1"
            value={form.contracts}
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
            value={form.expiry}
            onChange={(e) => set('expiry', e.target.value)}
          />
        </div>
        <div className="pp-field">
          <div className="pp-field-label">
            {form.direction === 'short' ? 'Premium collected / sh' : 'Premium paid / sh'}
          </div>
          <MoneyInput value={form.premium} onChange={(v) => set('premium', v)} placeholder="0.00" />
        </div>
      </div>

      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Date</div>
          <input
            className="pp-input mono"
            type="date"
            value={form.date}
            onChange={(e) => set('date', e.target.value)}
          />
        </div>
        <div className="pp-field">
          <div className="pp-field-label">Note (optional)</div>
          <input
            className="pp-input"
            value={form.note}
            onChange={(e) => set('note', e.target.value)}
            placeholder="thesis, source, etc."
          />
        </div>
      </div>
    </>
  );
}

function CloseFields({
  form, setForm, liveOpens, target,
}: {
  form: CloseForm;
  setForm: (f: CloseForm) => void;
  liveOpens: LiveOption[];
  target: LiveOption | null;
}) {
  const set = <K extends keyof CloseForm>(k: K, v: CloseForm[K]) =>
    setForm({ ...form, [k]: v });

  return (
    <>
      <div className="pp-field">
        <div className="pp-field-label">Closing which position?</div>
        <div className="pp-close-picker">
          {liveOpens.map((lo) => {
            const sign = lo.open.direction === 'short' ? '−' : '+';
            const label = `${sign}${lo.remaining_contracts} ${lo.open.option_type.toUpperCase()} $${lo.open.strike} exp ${lo.open.expiry} @ $${lo.open.premium}/sh`;
            return (
              <button
                key={lo.open.id}
                type="button"
                className={'pp-close-pick' + (form.target_id === lo.open.id ? ' on' : '')}
                onClick={() => set('target_id', lo.open.id)}
              >
                <span className={'pp-mini-glyph ' + (lo.open.direction === 'short' ? 'neg' : 'pos')}>
                  {lo.open.option_type === 'put' ? 'P' : 'C'}
                </span>
                <span className="pp-close-pick-label">{label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {target && (
        <div className="pp-form-grid cols-2">
          <div className="pp-field">
            <div className="pp-field-label">Contracts to close</div>
            <input
              className="pp-input mono"
              type="number"
              min="1"
              max={target.remaining_contracts}
              step="1"
              value={form.contracts}
              onChange={(e) => set('contracts', e.target.value)}
              placeholder={String(target.remaining_contracts)}
            />
            <div className="pp-field-hint">up to {target.remaining_contracts} remaining</div>
          </div>
          <div className="pp-field">
            <div className="pp-field-label">
              {target.open.direction === 'short' ? 'Premium paid back / sh' : 'Premium collected / sh'}
            </div>
            <MoneyInput value={form.premium} onChange={(v) => set('premium', v)} placeholder="0.00" />
            <div className="pp-field-hint">opened at ${target.open.premium}/sh</div>
          </div>
        </div>
      )}

      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Date</div>
          <input
            className="pp-input mono"
            type="date"
            value={form.date}
            onChange={(e) => set('date', e.target.value)}
          />
        </div>
        <div className="pp-field">
          <div className="pp-field-label">Note (optional)</div>
          <input
            className="pp-input"
            value={form.note}
            onChange={(e) => set('note', e.target.value)}
            placeholder="exit reason, etc."
          />
        </div>
      </div>
    </>
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

// Silence unused import warnings in case any are tree-shaken.
void {} as unknown as OptionTrade;
