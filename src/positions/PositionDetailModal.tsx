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
  initialTab?: Tab;
  /** Pre-selected live open for the close tab. */
  initialCloseTarget?: string;
  /** The expired option being resolved (when initialTab='resolve'). */
  resolveTrade?: OptionTrade;
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
  /** Update mutable fields on an existing OPEN trade. */
  onUpdateTrade?: (p: {
    id: string;
    contracts: number;
    strike: number;
    premium: number;
    expiry: string;
    trade_date: string;
    note?: string | null;
  }) => void;
  /** Sell shares manually. */
  onSellShares?: (p: {
    ticker: string;
    quantity: number;
    price: number;
    trade_date: string;
    note?: string | null;
  }) => void;
  /** Resolve an expired option (one of three flavors). */
  onResolveExpired?: (
    p:
      | { kind: 'expired'; open: OptionTrade; trade_date: string; note?: string | null }
      | {
          kind: 'rolled';
          open: OptionTrade;
          close_premium: number;
          close_date: string;
          new_strike: number;
          new_premium: number;
          new_expiry: string;
          new_open_date: string;
          note?: string | null;
        }
      | { kind: 'assigned'; open: OptionTrade; trade_date: string; note?: string | null },
  ) => void;
  onSetStatus: (p: { ticker: string; status: 'open' | 'closed' }) => void;
}

type Tab = 'open' | 'close' | 'edit' | 'sell-shares' | 'resolve';

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

interface EditForm {
  target_id: string;
  contracts: string;
  strike: string;
  premium: string;
  expiry: string;
  date: string;
  note: string;
}

const editFormFromTrade = (t: OptionTrade): EditForm => ({
  target_id: t.id,
  contracts: String(t.contracts),
  strike: String(t.strike),
  premium: String(t.premium),
  expiry: t.expiry,
  date: t.trade_date,
  note: t.note ?? '',
});

interface SellForm {
  quantity: string;
  price: string;
  date: string;
  note: string;
}
const blankSell = (): SellForm => ({
  quantity: '',
  price: '',
  date: todayIso(),
  note: '',
});

type ResolveKind = 'expired' | 'rolled' | 'assigned';
interface ResolveForm {
  kind: ResolveKind;
  // Date the resolution happened (close date for all kinds).
  trade_date: string;
  // Rolled-only:
  close_premium: string;
  new_strike: string;
  new_premium: string;
  new_expiry: string;
  new_open_date: string;
  note: string;
}
const blankResolve = (open: OptionTrade | undefined): ResolveForm => ({
  kind: 'expired',
  trade_date: open?.expiry ?? todayIso(),
  close_premium: '',
  new_strike: open ? String(open.strike) : '',
  new_premium: '',
  new_expiry: '',
  new_open_date: todayIso(),
  note: '',
});

export function PositionDetailModal({
  position,
  liveOpens,
  bucket,
  initialTab = 'open',
  initialCloseTarget,
  resolveTrade,
  onClose,
  onAddTrade,
  onUpdateTrade,
  onSellShares,
  onResolveExpired,
  onSetStatus,
}: Props) {
  const [tab, setTab] = useState<Tab>(
    initialTab === 'resolve' || initialTab === 'sell-shares'
      ? initialTab
      : liveOpens.length === 0
        ? 'open'
        : initialTab,
  );
  const [sellForm, setSellForm] = useState<SellForm>(blankSell());
  const [resolveForm, setResolveForm] = useState<ResolveForm>(blankResolve(resolveTrade));
  // If parent passes a new resolveTrade, reset the form for it.
  useEffect(() => {
    setResolveForm(blankResolve(resolveTrade));
  }, [resolveTrade?.id]);  // eslint-disable-line react-hooks/exhaustive-deps
  const [openForm, setOpenForm] = useState<OpenForm>(blankOpen());
  const [closeForm, setCloseForm] = useState<CloseForm>(
    blankClose(initialCloseTarget ?? liveOpens[0]?.open.id ?? ''),
  );
  // Edit tab — only LIVE opens (not fully closed). Sorted newest first.
  const editableOpens = useMemo<OptionTrade[]>(
    () =>
      liveOpens
        .map((l) => l.open)
        .sort((a, b) => b.trade_date.localeCompare(a.trade_date)),
    [liveOpens],
  );
  const [editForm, setEditForm] = useState<EditForm | null>(() =>
    editableOpens[0] ? editFormFromTrade(editableOpens[0]) : null,
  );
  useEffect(() => {
    // If the selected edit target disappears (e.g., parent re-renders),
    // fall back to the first available open.
    if (
      editForm &&
      !editableOpens.some((t) => t.id === editForm.target_id)
    ) {
      setEditForm(editableOpens[0] ? editFormFromTrade(editableOpens[0]) : null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editableOpens.length]);

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
    onClose(); // dismiss after submit; the parent toast confirms success/failure
  };

  // ── Edit tab math ──────────────────────────────────────────────
  const editTarget = useMemo<OptionTrade | null>(
    () =>
      editForm
        ? editableOpens.find((t) => t.id === editForm.target_id) ?? null
        : null,
    [editForm, editableOpens],
  );
  const canSubmitEdit =
    !!editForm &&
    !!editTarget &&
    !!onUpdateTrade &&
    parseFloat(editForm.contracts) > 0 &&
    parseFloat(editForm.strike) > 0 &&
    parseFloat(editForm.premium) >= 0 &&
    !!editForm.expiry &&
    !!editForm.date;

  const editDirty = !!(
    editForm &&
    editTarget &&
    (parseFloat(editForm.contracts) !== editTarget.contracts ||
      parseFloat(editForm.strike) !== editTarget.strike ||
      parseFloat(editForm.premium) !== editTarget.premium ||
      editForm.expiry !== editTarget.expiry ||
      editForm.date !== editTarget.trade_date ||
      (editForm.note || null) !== (editTarget.note || null))
  );

  const submitEdit = () => {
    if (!canSubmitEdit || !editForm || !onUpdateTrade) return;
    onUpdateTrade({
      id: editForm.target_id,
      contracts: parseInt(editForm.contracts, 10),
      strike: parseFloat(editForm.strike),
      premium: parseFloat(editForm.premium),
      expiry: editForm.expiry,
      trade_date: editForm.date,
      note: editForm.note || null,
    });
    onClose();
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
    onClose();
  };

  // ── Sell Shares math ───────────────────────────────────────────
  const sellQtyN = parseInt(sellForm.quantity, 10) || 0;
  const sellPriceN = parseFloat(sellForm.price) || 0;
  const canSubmitSell =
    !!onSellShares &&
    sellQtyN > 0 &&
    sellQtyN <= position.quantity &&
    sellPriceN >= 0 &&
    !!sellForm.date;
  const sellRealized = (sellPriceN - position.avg_cost) * sellQtyN;
  const submitSell = () => {
    if (!canSubmitSell || !onSellShares) return;
    onSellShares({
      ticker: position.ticker,
      quantity: sellQtyN,
      price: sellPriceN,
      trade_date: sellForm.date,
      note: sellForm.note || null,
    });
    setSellForm(blankSell());
    onClose();
  };

  // ── Resolve Expired math ───────────────────────────────────────
  // The trade being resolved was supplied via prop. Three paths:
  //   expired  — close at \$0, premium kept
  //   rolled   — close at buyback + open new at new strike/expiry
  //   assigned — short call → sells shares at strike (realized P&L preview)
  const resolveOpen = resolveTrade;
  const isResolveShortCall =
    !!resolveOpen &&
    resolveOpen.direction === 'short' &&
    resolveOpen.option_type === 'call';
  const isResolveShortPut =
    !!resolveOpen &&
    resolveOpen.direction === 'short' &&
    resolveOpen.option_type === 'put';
  const resolveAssignedSharePnl =
    resolveOpen && isResolveShortCall
      ? (resolveOpen.strike - position.avg_cost) * resolveOpen.contracts * 100
      : 0;
  const resolveAssignedNewAvg =
    resolveOpen && isResolveShortPut
      ? (() => {
          const newShares = resolveOpen.contracts * 100;
          const totalShares = position.quantity + newShares;
          return totalShares > 0
            ? (position.quantity * position.avg_cost +
                newShares * resolveOpen.strike) /
                totalShares
            : resolveOpen.strike;
        })()
      : null;
  const resolveRolledClosePremiumN = parseFloat(resolveForm.close_premium) || 0;
  const resolveRolledNewStrikeN = parseFloat(resolveForm.new_strike) || 0;
  const resolveRolledNewPremiumN = parseFloat(resolveForm.new_premium) || 0;

  const canSubmitResolve = (() => {
    if (!onResolveExpired || !resolveOpen) return false;
    if (resolveForm.kind === 'expired') return !!resolveForm.trade_date;
    if (resolveForm.kind === 'assigned') return !!resolveForm.trade_date;
    // rolled
    return (
      !!resolveForm.trade_date &&
      resolveRolledClosePremiumN >= 0 &&
      resolveRolledNewStrikeN > 0 &&
      resolveRolledNewPremiumN >= 0 &&
      !!resolveForm.new_expiry &&
      !!resolveForm.new_open_date
    );
  })();

  const submitResolve = () => {
    if (!canSubmitResolve || !onResolveExpired || !resolveOpen) return;
    if (resolveForm.kind === 'expired') {
      onResolveExpired({
        kind: 'expired',
        open: resolveOpen,
        trade_date: resolveForm.trade_date,
        note: resolveForm.note || null,
      });
    } else if (resolveForm.kind === 'assigned') {
      onResolveExpired({
        kind: 'assigned',
        open: resolveOpen,
        trade_date: resolveForm.trade_date,
        note: resolveForm.note || null,
      });
    } else {
      onResolveExpired({
        kind: 'rolled',
        open: resolveOpen,
        close_premium: resolveRolledClosePremiumN,
        close_date: resolveForm.trade_date,
        new_strike: resolveRolledNewStrikeN,
        new_premium: resolveRolledNewPremiumN,
        new_expiry: resolveForm.new_expiry,
        new_open_date: resolveForm.new_open_date,
        note: resolveForm.note || null,
      });
    }
    onClose();
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
          <button
            className={'pp-tab' + (tab === 'edit' ? ' on' : '') + (editableOpens.length === 0 ? ' disabled' : '')}
            onClick={() => editableOpens.length > 0 && setTab('edit')}
            disabled={editableOpens.length === 0 || !onUpdateTrade}
            title={
              !onUpdateTrade
                ? 'Edit not wired'
                : editableOpens.length === 0
                  ? 'No trades to edit'
                  : ''
            }
          >
            Edit<span className="pp-tab-count">{editableOpens.length}</span>
          </button>
          <button
            className={
              'pp-tab' +
              (tab === 'sell-shares' ? ' on' : '') +
              (position.quantity === 0 ? ' disabled' : '')
            }
            onClick={() => position.quantity > 0 && setTab('sell-shares')}
            disabled={position.quantity === 0 || !onSellShares}
            title={
              !onSellShares
                ? 'Sell shares not wired'
                : position.quantity === 0
                  ? 'No shares to sell'
                  : ''
            }
          >
            Sell shares
          </button>
          {resolveOpen && (
            <button
              className={'pp-tab' + (tab === 'resolve' ? ' on' : '')}
              onClick={() => setTab('resolve')}
              disabled={!onResolveExpired}
            >
              Resolve
            </button>
          )}
        </div>

        {/* SIDECAR */}
        <div className="pp-sidecar">
          <div className="pp-form">
            {tab === 'open' && (
              <OpenFields form={openForm} setForm={setOpenForm} />
            )}
            {tab === 'close' && (
              <CloseFields
                form={closeForm}
                setForm={setCloseForm}
                liveOpens={liveOpens}
                target={closeTarget}
              />
            )}
            {tab === 'edit' && (
              <EditFields
                form={editForm}
                setForm={setEditForm}
                opens={editableOpens}
                target={editTarget}
              />
            )}
            {tab === 'sell-shares' && (
              <SellSharesFields
                form={sellForm}
                setForm={setSellForm}
                maxQty={position.quantity}
                avgCost={position.avg_cost}
              />
            )}
            {tab === 'resolve' && resolveOpen && (
              <ResolveFields
                form={resolveForm}
                setForm={setResolveForm}
                open={resolveOpen}
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
                {tab === 'open' ? 'New trade preview'
                  : tab === 'close' ? 'Realized P&L'
                  : tab === 'edit' ? 'Edit preview'
                  : tab === 'sell-shares' ? 'Sale preview'
                  : tab === 'resolve' ? 'Resolution preview'
                  : 'Preview'}
              </div>
              {tab === 'open' && (
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
              )}
              {tab === 'close' && (
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
              {tab === 'edit' && editTarget && editForm && (() => {
                const newTotal =
                  (parseFloat(editForm.contracts) || 0) * 100 *
                  (parseFloat(editForm.premium) || 0);
                const isCashIn = editTarget.direction === 'short';
                const signed = isCashIn ? newTotal : -newTotal;
                return (
                  <>
                    <div className={'pp-rail-bignum ' + (signed > 0 ? 'pos' : signed < 0 ? 'neg' : '')}>
                      {signed === 0
                        ? '—'
                        : signed > 0
                          ? fmtUSD(signed)
                          : '−' + fmtUSD(Math.abs(signed))}
                    </div>
                    <div className="pp-rail-sub">
                      {isCashIn ? 'premium collected' : 'premium paid'}
                      {editDirty && ' · unsaved'}
                    </div>
                  </>
                );
              })()}
              {tab === 'sell-shares' && (
                <>
                  <div className={'pp-rail-bignum ' + (sellRealized > 0 ? 'pos' : sellRealized < 0 ? 'neg' : '')}>
                    {sellQtyN === 0
                      ? '—'
                      : sellRealized >= 0
                        ? fmtUSD(sellRealized)
                        : '−' + fmtUSD(Math.abs(sellRealized))}
                  </div>
                  <div className="pp-rail-sub">
                    {sellQtyN > 0
                      ? `${sellQtyN} sh × (${fmtUSD2(sellPriceN)} − ${fmtUSD2(position.avg_cost)})`
                      : 'enter qty + price'}
                  </div>
                </>
              )}
              {tab === 'resolve' && resolveOpen && (
                <>
                  {resolveForm.kind === 'expired' && (
                    <>
                      <div className="pp-rail-bignum pos">
                        {fmtUSD(resolveOpen.contracts * 100 * resolveOpen.premium)}
                      </div>
                      <div className="pp-rail-sub">
                        full premium kept (expired worthless)
                      </div>
                    </>
                  )}
                  {resolveForm.kind === 'assigned' && isResolveShortCall && (
                    <>
                      <div className={'pp-rail-bignum ' + (resolveAssignedSharePnl > 0 ? 'pos' : resolveAssignedSharePnl < 0 ? 'neg' : '')}>
                        {resolveAssignedSharePnl >= 0
                          ? fmtUSD(resolveAssignedSharePnl)
                          : '−' + fmtUSD(Math.abs(resolveAssignedSharePnl))}
                      </div>
                      <div className="pp-rail-sub">
                        stock realized · {resolveOpen.contracts * 100} sh × (${resolveOpen.strike} − {fmtUSD2(position.avg_cost)})
                      </div>
                    </>
                  )}
                  {resolveForm.kind === 'assigned' && isResolveShortPut && resolveAssignedNewAvg != null && (
                    <>
                      <div className="pp-rail-bignum">{fmtUSD2(resolveAssignedNewAvg)}</div>
                      <div className="pp-rail-sub">
                        new avg cost after buying {resolveOpen.contracts * 100} sh @ ${resolveOpen.strike}
                      </div>
                    </>
                  )}
                  {resolveForm.kind === 'rolled' && (
                    <>
                      {(() => {
                        const realized =
                          resolveOpen.direction === 'short'
                            ? (resolveOpen.premium - resolveRolledClosePremiumN) * resolveOpen.contracts * 100
                            : (resolveRolledClosePremiumN - resolveOpen.premium) * resolveOpen.contracts * 100;
                        return (
                          <>
                            <div className={'pp-rail-bignum ' + (realized > 0 ? 'pos' : realized < 0 ? 'neg' : '')}>
                              {realized >= 0
                                ? fmtUSD(realized)
                                : '−' + fmtUSD(Math.abs(realized))}
                            </div>
                            <div className="pp-rail-sub">
                              realized on close · new open follows
                            </div>
                          </>
                        );
                      })()}
                    </>
                  )}
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
            {tab === 'open' && (
              <button className="pp-btn pp-btn-neon" onClick={submitOpen} disabled={!canSubmitOpen}>
                ✓ Open position
              </button>
            )}
            {tab === 'close' && (
              <button className="pp-btn pp-btn-neon" onClick={submitClose} disabled={!canSubmitClose}>
                ✓ Close position
              </button>
            )}
            {tab === 'edit' && (
              <button
                className="pp-btn pp-btn-neon"
                onClick={submitEdit}
                disabled={!canSubmitEdit || !editDirty}
                title={!editDirty ? 'No changes' : ''}
              >
                ✓ Save changes
              </button>
            )}
            {tab === 'sell-shares' && (
              <button
                className="pp-btn pp-btn-neon"
                onClick={submitSell}
                disabled={!canSubmitSell}
              >
                ✓ Sell shares
              </button>
            )}
            {tab === 'resolve' && (
              <button
                className="pp-btn pp-btn-neon"
                onClick={submitResolve}
                disabled={!canSubmitResolve}
              >
                ✓ Resolve
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
        <div className="pp-close-picker" role="radiogroup">
          {liveOpens.map((lo) => {
            const isSelected = form.target_id === lo.open.id;
            const sign = lo.open.direction === 'short' ? '−' : '+';
            return (
              <label
                key={lo.open.id}
                className={'pp-close-pick' + (isSelected ? ' on' : '')}
              >
                <input
                  type="radio"
                  name="close-target"
                  value={lo.open.id}
                  checked={isSelected}
                  onChange={() => set('target_id', lo.open.id)}
                  className="pp-close-pick-radio"
                />
                <span className="pp-close-pick-dot" aria-hidden />
                <span className={'pp-mini-glyph ' + (lo.open.direction === 'short' ? 'neg' : 'pos')}>
                  {lo.open.option_type === 'put' ? 'P' : 'C'}
                </span>
                <div className="pp-close-pick-body">
                  <div className="pp-close-pick-headline">
                    {sign}{lo.remaining_contracts} {lo.open.option_type.toUpperCase()} ${lo.open.strike}
                  </div>
                  <div className="pp-close-pick-sub">
                    exp {lo.open.expiry} · opened @ ${lo.open.premium}/sh
                  </div>
                </div>
              </label>
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

// ─────────────────────────────────────────────────────────────────────
// Edit fields — pick an existing OPEN trade, mutate its fields.
// option_type and direction are deliberately locked (matched closes
// reference them). Delete + re-create if you really need to change those.
function EditFields({
  form, setForm, opens, target,
}: {
  form: EditForm | null;
  setForm: (f: EditForm | null) => void;
  opens: OptionTrade[];
  target: OptionTrade | null;
}) {
  if (opens.length === 0) {
    return (
      <div className="pp-field" style={{ padding: '24px 0', color: 'var(--navi-fg3)' }}>
        No opens to edit yet.
      </div>
    );
  }
  const set = <K extends keyof EditForm>(k: K, v: EditForm[K]) => {
    if (!form) return;
    setForm({ ...form, [k]: v });
  };
  const selectTrade = (id: string) => {
    const t = opens.find((x) => x.id === id);
    if (t) setForm(editFormFromTrade(t));
  };

  return (
    <>
      <div className="pp-field">
        <div className="pp-field-label">Which trade?</div>
        <div className="pp-close-picker" role="radiogroup">
          {opens.map((t) => {
            const isSelected = form?.target_id === t.id;
            const sign = t.direction === 'short' ? '−' : '+';
            return (
              <label
                key={t.id}
                className={'pp-close-pick' + (isSelected ? ' on' : '')}
              >
                <input
                  type="radio"
                  name="edit-target"
                  value={t.id}
                  checked={isSelected}
                  onChange={() => selectTrade(t.id)}
                  className="pp-close-pick-radio"
                />
                <span className="pp-close-pick-dot" aria-hidden />
                <span className={'pp-mini-glyph ' + (t.direction === 'short' ? 'neg' : 'pos')}>
                  {t.option_type === 'put' ? 'P' : 'C'}
                </span>
                <div className="pp-close-pick-body">
                  <div className="pp-close-pick-headline">
                    {sign}{t.contracts} {t.option_type.toUpperCase()} ${t.strike}
                  </div>
                  <div className="pp-close-pick-sub">
                    exp {t.expiry} · opened {t.trade_date} @ ${t.premium}/sh
                  </div>
                </div>
              </label>
            );
          })}
        </div>
      </div>

      {target && form && (
        <>
          <div className="pp-form-grid cols-2">
            <div className="pp-field">
              <div className="pp-field-label">Contracts</div>
              <input
                className="pp-input mono"
                type="number"
                min="1"
                step="1"
                value={form.contracts}
                onChange={(e) => set('contracts', e.target.value)}
              />
            </div>
            <div className="pp-field">
              <div className="pp-field-label">Strike</div>
              <MoneyInput value={form.strike} onChange={(v) => set('strike', v)} placeholder="0.00" />
            </div>
          </div>
          <div className="pp-form-grid cols-2">
            <div className="pp-field">
              <div className="pp-field-label">
                Premium / sh ({target.direction === 'short' ? 'collected' : 'paid'})
              </div>
              <MoneyInput value={form.premium} onChange={(v) => set('premium', v)} placeholder="0.00" />
            </div>
            <div className="pp-field">
              <div className="pp-field-label">Expiry</div>
              <input
                className="pp-input mono"
                type="date"
                value={form.expiry}
                onChange={(e) => set('expiry', e.target.value)}
              />
            </div>
          </div>
          <div className="pp-form-grid cols-2">
            <div className="pp-field">
              <div className="pp-field-label">Trade date</div>
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
                placeholder="adjustment reason, etc."
              />
            </div>
          </div>
          <div className="pp-field-hint" style={{ marginTop: 8 }}>
            Side ({target.direction} {target.option_type}) is locked — delete
            and re-create if you need to flip it.
          </div>
        </>
      )}
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

// ─────────────────────────────────────────────────────────────────────
// Sell Shares fields
function SellSharesFields({
  form, setForm, maxQty, avgCost,
}: {
  form: SellForm;
  setForm: (f: SellForm) => void;
  maxQty: number;
  avgCost: number;
}) {
  const set = <K extends keyof SellForm>(k: K, v: SellForm[K]) =>
    setForm({ ...form, [k]: v });
  return (
    <>
      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Quantity</div>
          <input
            className="pp-input mono"
            type="number"
            min="1"
            max={maxQty}
            step="1"
            value={form.quantity}
            onChange={(e) => set('quantity', e.target.value)}
            placeholder={String(maxQty)}
          />
          <div className="pp-field-hint">up to {fmtQty(maxQty)} on hand</div>
        </div>
        <div className="pp-field">
          <div className="pp-field-label">Price / share</div>
          <MoneyInput value={form.price} onChange={(v) => set('price', v)} placeholder="0.00" />
          <div className="pp-field-hint">avg basis {fmtUSD2(avgCost)}</div>
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
            placeholder="reason, broker fill ID, etc."
          />
        </div>
      </div>
    </>
  );
}

// ─────────────────────────────────────────────────────────────────────
// Resolve Expired fields — three modes (expired / rolled / assigned).
function ResolveFields({
  form, setForm, open,
}: {
  form: ResolveForm;
  setForm: (f: ResolveForm) => void;
  open: OptionTrade;
}) {
  const set = <K extends keyof ResolveForm>(k: K, v: ResolveForm[K]) =>
    setForm({ ...form, [k]: v });
  const isCall = open.option_type === 'call';
  return (
    <>
      <div className="pp-field">
        <div className="pp-field-label">Resolving this expired position</div>
        <div className="pp-resolve-card">
          <span className={'pp-mini-glyph ' + (open.direction === 'short' ? 'neg' : 'pos')}>
            {isCall ? 'C' : 'P'}
          </span>
          <span className="pp-resolve-meta">
            {open.direction === 'short' ? '−' : '+'}
            {open.contracts} {open.option_type.toUpperCase()} ${open.strike}
            <span className="pp-resolve-exp"> · exp {open.expiry}</span>
          </span>
          <span className="pp-resolve-prem">opened @ ${open.premium}/sh</span>
        </div>
      </div>

      <div className="pp-field">
        <div className="pp-field-label">What happened?</div>
        <div className="pp-source-seg">
          {(
            [
              ['expired', 'Expired worthless'],
              ['rolled', 'Rolled'],
              ['assigned', 'Exercised / Assigned'],
            ] as const
          ).map(([k, label]) => (
            <button
              key={k}
              type="button"
              className={'pp-source-opt' + (form.kind === k ? ' on' : '')}
              onClick={() => set('kind', k)}
            >
              <span>{label}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">
            {form.kind === 'rolled' ? 'Close date' : 'Resolution date'}
          </div>
          <input
            className="pp-input mono"
            type="date"
            value={form.trade_date}
            onChange={(e) => set('trade_date', e.target.value)}
          />
          <div className="pp-field-hint">defaults to expiry ({open.expiry})</div>
        </div>
        {form.kind === 'rolled' && (
          <div className="pp-field">
            <div className="pp-field-label">
              Close premium / sh ({open.direction === 'short' ? 'paid back' : 'collected'})
            </div>
            <MoneyInput value={form.close_premium} onChange={(v) => set('close_premium', v)} placeholder="0.00" />
            <div className="pp-field-hint">opened @ ${open.premium}/sh</div>
          </div>
        )}
      </div>

      {form.kind === 'rolled' && (
        <>
          <div className="pp-form-grid cols-2">
            <div className="pp-field">
              <div className="pp-field-label">New strike</div>
              <MoneyInput value={form.new_strike} onChange={(v) => set('new_strike', v)} placeholder={String(open.strike)} />
            </div>
            <div className="pp-field">
              <div className="pp-field-label">New premium / sh</div>
              <MoneyInput value={form.new_premium} onChange={(v) => set('new_premium', v)} placeholder="0.00" />
            </div>
          </div>
          <div className="pp-form-grid cols-2">
            <div className="pp-field">
              <div className="pp-field-label">New expiry</div>
              <input
                className="pp-input mono"
                type="date"
                value={form.new_expiry}
                onChange={(e) => set('new_expiry', e.target.value)}
              />
            </div>
            <div className="pp-field">
              <div className="pp-field-label">New trade date</div>
              <input
                className="pp-input mono"
                type="date"
                value={form.new_open_date}
                onChange={(e) => set('new_open_date', e.target.value)}
              />
            </div>
          </div>
        </>
      )}

      <div className="pp-field">
        <div className="pp-field-label">Note (optional)</div>
        <input
          className="pp-input"
          value={form.note}
          onChange={(e) => set('note', e.target.value)}
          placeholder="anything to remember about this resolution"
        />
      </div>
    </>
  );
}

// Silence unused import warnings in case any are tree-shaken.
void {} as unknown as OptionTrade;
