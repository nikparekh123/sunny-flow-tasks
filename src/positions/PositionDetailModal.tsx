import { useEffect, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
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
  /** Close price on the resolveTrade's expiry date — if available,
   *  the Resolve flow uses it to default the radio (ITM → Exercised,
   *  OTM → Expired worthless). Null when no snapshot exists. */
  resolveExpiryClose?: number | null;
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
  /** Buy more shares of an existing ticker. overrideAvgCost lets the
   *  caller skip the weighted-average computation when broker reporting
   *  has already given them the post-buy avg directly. */
  onBuyShares?: (p: {
    ticker: string;
    quantity: number;
    price: number;
    overrideAvgCost?: number;
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

type Tab = 'open' | 'close' | 'edit' | 'shares' | 'resolve';

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
/** Decide which resolution kind to default to. ITM → assigned,
 *  OTM → expired. When we don't have a close snapshot (null), fall
 *  back to expired (most common case for OTM income premium). */
function defaultResolveKind(
  open: OptionTrade | undefined,
  closeAtExpiry: number | null | undefined,
): ResolveKind {
  if (!open || closeAtExpiry == null) return 'expired';
  // For a SHORT call, ITM = close >= strike → assigned (shares called).
  // For a SHORT put,  ITM = close <= strike → assigned (shares put to us).
  // For LONG sides (rare for this user), ITM means they'd be exercising.
  const isCall = open.option_type === 'call';
  const itm = isCall
    ? closeAtExpiry >= open.strike
    : closeAtExpiry <= open.strike;
  return itm ? 'assigned' : 'expired';
}

const blankResolve = (
  open: OptionTrade | undefined,
  closeAtExpiry?: number | null,
): ResolveForm => ({
  kind: defaultResolveKind(open, closeAtExpiry),
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
  resolveExpiryClose,
  onClose,
  onAddTrade,
  onUpdateTrade,
  onBuyShares,
  onSellShares,
  onResolveExpired,
  onSetStatus,
}: Props) {
  const [tab, setTab] = useState<Tab>(
    initialTab === 'resolve' || initialTab === 'shares'
      ? initialTab
      : liveOpens.length === 0
        ? 'open'
        : initialTab,
  );
  // Mode toggle inside the Shares tab.
  const [sharesMode, setSharesMode] = useState<'buy' | 'sell'>(
    position.quantity > 0 ? 'sell' : 'buy',
  );
  const [sellForm, setSellForm] = useState<SellForm>(blankSell());
  const [resolveForm, setResolveForm] = useState<ResolveForm>(
    blankResolve(resolveTrade, resolveExpiryClose),
  );
  // If parent passes a new resolveTrade (or the close snapshot lands
  // asynchronously), reset the form with the right default.
  useEffect(() => {
    setResolveForm(blankResolve(resolveTrade, resolveExpiryClose));
  }, [resolveTrade?.id, resolveExpiryClose]);  // eslint-disable-line react-hooks/exhaustive-deps
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

  // Confirm-dialog state. When set, an overlay covers the modal with a
  // human-readable summary of the action about to fire — the ticker is
  // rendered LARGE in neon so the user catches mismatches like
  // "I meant META but the modal is on WDAY" before clicking through.
  // Each request* helper below builds one of these and stashes it here;
  // the dialog's confirm button invokes `action`, which runs the real
  // submit* and closes the parent modal.
  const [confirm, setConfirm] = useState<ConfirmState | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // While the confirm dialog is up, let it handle Esc so we don't
      // dismiss the whole modal underneath. Cleared by the dialog itself.
      if (confirm) return;
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = '';
    };
  }, [onClose, confirm]);

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

  // ── Shares tab math (handles both Buy and Sell) ────────────────
  // Avg-cost override: when the user has the actual post-trade avg from
  // their broker (FIFO splits, wash-sale adjustments, etc.), letting them
  // enter it directly is more accurate than re-deriving from per-share
  // price. Optional — defaults off, computed weighted avg shown otherwise.
  const [overrideAvg, setOverrideAvg] = useState(false);
  const [overrideAvgInput, setOverrideAvgInput] = useState('');
  const overrideAvgN = parseFloat(overrideAvgInput) || 0;

  const sharesQtyN = parseInt(sellForm.quantity, 10) || 0;
  const sharesPriceN = parseFloat(sellForm.price) || 0;
  // Sell preview
  const sellRealized = (sharesPriceN - position.avg_cost) * sharesQtyN;
  // Buy preview — weighted avg cost after the buy, OR the override.
  const buyNewQty = position.quantity + sharesQtyN;
  const computedAvg =
    buyNewQty > 0
      ? (position.quantity * position.avg_cost + sharesQtyN * sharesPriceN) / buyNewQty
      : sharesPriceN;
  const buyNewAvg = overrideAvg && overrideAvgN > 0 ? overrideAvgN : computedAvg;

  // When override is on, the per-share price field becomes optional —
  // we only require the override-avg to be set. Otherwise the original
  // qty + price guard applies.
  const sharesPriceOk = overrideAvg ? overrideAvgN > 0 : sharesPriceN >= 0;
  const canSubmitShares =
    sharesQtyN > 0 &&
    sharesPriceOk &&
    !!sellForm.date &&
    (sharesMode === 'buy'
      ? !!onBuyShares
      : !!onSellShares && sharesQtyN <= position.quantity);
  const submitShares = () => {
    if (!canSubmitShares) return;
    const payload = {
      ticker: position.ticker,
      quantity: sharesQtyN,
      price: sharesPriceN,
      trade_date: sellForm.date,
      note: sellForm.note || null,
    };
    if (sharesMode === 'buy' && onBuyShares) {
      onBuyShares({
        ...payload,
        ...(overrideAvg && overrideAvgN > 0 ? { overrideAvgCost: overrideAvgN } : {}),
      });
    } else if (sharesMode === 'sell' && onSellShares) onSellShares(payload);
    setSellForm(blankSell());
    setOverrideAvg(false);
    setOverrideAvgInput('');
    onClose();
  };

  // ── Resolve Expired math ───────────────────────────────────────
  // The trade being resolved was supplied via prop. Three paths:
  //   expired  — close at \$0, premium kept
  //   rolled   — close at buyback + open new at new strike/expiry
  //   assigned — short call → sells shares at strike (realized P&L preview)
  //
  // Fall back to the first expired live open on this ticker if the parent
  // didn't pass an explicit resolveTrade — that way the Resolve tab is
  // discoverable even when the user opens the modal via the ticker name
  // (rather than clicking the specific expired cell in the trades matrix).
  //
  // `expiry <= today` (not <) so options expiring TODAY also qualify —
  // after market close on expiry day the user already knows ITM/OTM and
  // should be able to resolve same-day.
  const today = todayIso();
  const firstExpiredOpen = useMemo(
    () => liveOpens.find((lo) => lo.open.expiry <= today)?.open,
    [liveOpens, today],
  );
  const resolveOpen = resolveTrade ?? firstExpiredOpen;
  const expiredCount = useMemo(
    () => liveOpens.filter((lo) => lo.open.expiry <= today).length,
    [liveOpens, today],
  );
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

  // ── Confirm-step builders ────────────────────────────────────────
  // Each request* assembles a human-readable summary from the current
  // form, stashes it in `confirm` state, and lets the user review the
  // ticker + numbers before the underlying submit* fires. The dialog's
  // Confirm button calls back into the submit* declared above.
  const optWord = (t: OptionType) => (t === 'call' ? 'call' : 'put');
  const plural = (n: number, base: string) => `${base}${n === 1 ? '' : 's'}`;

  const requestOpen = () => {
    if (!canSubmitOpen) return;
    const contracts = parseInt(openForm.contracts, 10);
    const premium = parseFloat(openForm.premium);
    const strike = parseFloat(openForm.strike);
    const total = contracts * 100 * premium;
    const isShort = openForm.direction === 'short';
    const verb = isShort ? 'Selling' : 'Buying';
    const moneyLabel = isShort ? 'Premium collected' : 'Premium paid';
    setConfirm({
      ticker: position.ticker,
      title: 'Confirm open',
      heading: `${verb} ${contracts} ${openForm.direction} ${plural(contracts, optWord(openForm.option_type))}`,
      lines: [
        { label: 'Strike', value: fmtUSD2(strike) },
        { label: 'Expiry', value: fmtDateHuman(openForm.expiry) },
        { label: 'Premium', value: `${fmtUSD2(premium)} / sh` },
        { label: moneyLabel, value: fmtUSD(total), tone: isShort ? 'positive' : 'negative' },
      ],
      confirmLabel: 'Open position',
      action: () => { setConfirm(null); submitOpen(); },
    });
  };

  const requestClose = () => {
    if (!canSubmitClose || !closeTarget) return;
    const o = closeTarget.open;
    setConfirm({
      ticker: position.ticker,
      title: 'Confirm close',
      heading: `Closing ${closeContractsN} ${o.direction} ${plural(closeContractsN, optWord(o.option_type))}`,
      lines: [
        { label: 'Strike', value: fmtUSD2(o.strike) },
        { label: 'Expiry', value: fmtDateHuman(o.expiry) },
        { label: 'Buyback', value: `${fmtUSD2(closePremiumN)} / sh` },
        {
          label: 'Realized P&L',
          value: closeRealized >= 0 ? `+${fmtUSD(closeRealized)}` : `−${fmtUSD(Math.abs(closeRealized))}`,
          tone: closeRealized >= 0 ? 'positive' : 'negative',
        },
      ],
      confirmLabel: 'Close position',
      action: () => { setConfirm(null); submitClose(); },
    });
  };

  const requestEdit = () => {
    if (!canSubmitEdit || !editTarget || !editForm) return;
    // Show only changed fields — keeps the diff scannable when the user
    // only nudged the premium, etc.
    const lines: ConfirmLine[] = [];
    const newContracts = parseInt(editForm.contracts, 10);
    const newStrike = parseFloat(editForm.strike);
    const newPremium = parseFloat(editForm.premium);
    if (newContracts !== editTarget.contracts) {
      lines.push({ label: 'Contracts', value: `${editTarget.contracts} → ${newContracts}` });
    }
    if (newStrike !== editTarget.strike) {
      lines.push({ label: 'Strike', value: `${fmtUSD2(editTarget.strike)} → ${fmtUSD2(newStrike)}` });
    }
    if (newPremium !== editTarget.premium) {
      lines.push({ label: 'Premium', value: `${fmtUSD2(editTarget.premium)} → ${fmtUSD2(newPremium)}` });
    }
    if (editForm.expiry !== editTarget.expiry) {
      lines.push({ label: 'Expiry', value: `${fmtDateHuman(editTarget.expiry)} → ${fmtDateHuman(editForm.expiry)}` });
    }
    if (editForm.date !== editTarget.trade_date) {
      lines.push({ label: 'Trade date', value: `${fmtDateHuman(editTarget.trade_date)} → ${fmtDateHuman(editForm.date)}` });
    }
    setConfirm({
      ticker: position.ticker,
      title: 'Confirm edit',
      heading: `Editing ${editTarget.direction} ${optWord(editTarget.option_type)} · strike ${fmtUSD2(editTarget.strike)} exp ${fmtDateHuman(editTarget.expiry)}`,
      lines: lines.length > 0 ? lines : [{ label: 'No field changes', value: '—' }],
      confirmLabel: 'Save changes',
      action: () => { setConfirm(null); submitEdit(); },
    });
  };

  const requestShares = () => {
    if (!canSubmitShares) return;
    if (sharesMode === 'buy') {
      const cost = sharesQtyN * sharesPriceN;
      setConfirm({
        ticker: position.ticker,
        title: 'Confirm buy shares',
        heading: `Buying ${sharesQtyN.toLocaleString()} ${plural(sharesQtyN, 'share')} of ${position.ticker}`,
        lines: [
          { label: 'Price', value: `${fmtUSD2(sharesPriceN)} / sh` },
          { label: 'Cost', value: fmtUSD(cost), tone: 'negative' },
          { label: 'New avg basis', value: fmtUSD2(buyNewAvg) },
          { label: 'New share count', value: buyNewQty.toLocaleString() },
          ...(overrideAvg && overrideAvgN > 0
            ? [{ label: 'Avg cost override', value: fmtUSD2(overrideAvgN), tone: 'emphasis' as const }]
            : []),
        ],
        confirmLabel: 'Buy shares',
        action: () => { setConfirm(null); submitShares(); },
      });
    } else {
      const proceeds = sharesQtyN * sharesPriceN;
      setConfirm({
        ticker: position.ticker,
        title: 'Confirm sell shares',
        heading: `Selling ${sharesQtyN.toLocaleString()} ${plural(sharesQtyN, 'share')} of ${position.ticker}`,
        lines: [
          { label: 'Price', value: `${fmtUSD2(sharesPriceN)} / sh` },
          { label: 'Proceeds', value: fmtUSD(proceeds), tone: 'positive' },
          {
            label: 'Realized P&L',
            value: sellRealized >= 0 ? `+${fmtUSD(sellRealized)}` : `−${fmtUSD(Math.abs(sellRealized))}`,
            tone: sellRealized >= 0 ? 'positive' : 'negative',
          },
          { label: 'Remaining shares', value: (position.quantity - sharesQtyN).toLocaleString() },
        ],
        confirmLabel: 'Sell shares',
        action: () => { setConfirm(null); submitShares(); },
      });
    }
  };

  const requestResolve = () => {
    if (!canSubmitResolve || !resolveOpen) return;
    const o = resolveOpen;
    const optDesc = `${o.contracts} ${o.direction} ${plural(o.contracts, optWord(o.option_type))} · strike ${fmtUSD2(o.strike)} exp ${fmtDateHuman(o.expiry)}`;

    if (resolveForm.kind === 'expired') {
      const premKept = o.contracts * 100 * o.premium;
      const signed = o.direction === 'short' ? premKept : -premKept;
      setConfirm({
        ticker: position.ticker,
        title: 'Confirm expire worthless',
        heading: `Expiring worthless: ${optDesc}`,
        lines: [
          { label: 'Trade date', value: fmtDateHuman(resolveForm.trade_date) },
          {
            label: o.direction === 'short' ? 'Premium kept' : 'Premium lost',
            value: signed >= 0 ? `+${fmtUSD(signed)}` : `−${fmtUSD(Math.abs(signed))}`,
            tone: signed >= 0 ? 'positive' : 'negative',
          },
        ],
        confirmLabel: 'Mark expired',
        action: () => { setConfirm(null); submitResolve(); },
      });
    } else if (resolveForm.kind === 'assigned') {
      const lines: ConfirmLine[] = [{ label: 'Trade date', value: fmtDateHuman(resolveForm.trade_date) }];
      if (isResolveShortCall) {
        lines.push({ label: 'Shares delivered', value: (o.contracts * 100).toLocaleString() });
        lines.push({ label: 'Sold at', value: `${fmtUSD2(o.strike)} / sh` });
        lines.push({
          label: 'Realized P&L on shares',
          value: resolveAssignedSharePnl >= 0 ? `+${fmtUSD(resolveAssignedSharePnl)}` : `−${fmtUSD(Math.abs(resolveAssignedSharePnl))}`,
          tone: resolveAssignedSharePnl >= 0 ? 'positive' : 'negative',
        });
      } else if (isResolveShortPut) {
        lines.push({ label: 'Shares put to you', value: (o.contracts * 100).toLocaleString() });
        lines.push({ label: 'Bought at', value: `${fmtUSD2(o.strike)} / sh` });
        if (resolveAssignedNewAvg != null) {
          lines.push({ label: 'New avg basis', value: fmtUSD2(resolveAssignedNewAvg) });
        }
      }
      setConfirm({
        ticker: position.ticker,
        title: 'Confirm assignment',
        heading: `Assigning: ${optDesc}`,
        lines,
        confirmLabel: 'Mark assigned',
        action: () => { setConfirm(null); submitResolve(); },
      });
    } else {
      // rolled
      setConfirm({
        ticker: position.ticker,
        title: 'Confirm roll',
        heading: `Rolling: ${optDesc}`,
        lines: [
          { label: 'Close at', value: `${fmtUSD2(resolveRolledClosePremiumN)} / sh` },
          { label: 'New strike', value: fmtUSD2(resolveRolledNewStrikeN) },
          { label: 'New premium', value: `${fmtUSD2(resolveRolledNewPremiumN)} / sh` },
          { label: 'New expiry', value: fmtDateHuman(resolveForm.new_expiry) },
        ],
        confirmLabel: 'Confirm roll',
        action: () => { setConfirm(null); submitResolve(); },
      });
    }
  };

  const requestMarkClosed = () => {
    setConfirm({
      ticker: position.ticker,
      title: isClosed ? 'Confirm reopen' : 'Confirm mark closed',
      heading: isClosed
        ? `Reopening ${position.ticker} position`
        : `Marking ${position.ticker} position fully closed`,
      lines: isClosed
        ? [{ label: 'Effect', value: 'Position returns to open status (manual override).' }]
        : [{ label: 'Effect', value: 'Position is flagged closed. Manual override — does not adjust trades.', tone: 'emphasis' }],
      confirmLabel: isClosed ? 'Reopen position' : 'Mark closed',
      tone: isClosed ? 'neutral' : 'danger',
      action: () => {
        setConfirm(null);
        onSetStatus({ ticker: position.ticker, status: isClosed ? 'open' : 'closed' });
      },
    });
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
            className={'pp-tab' + (tab === 'shares' ? ' on' : '')}
            onClick={() => setTab('shares')}
            disabled={!onBuyShares && !onSellShares}
            title={
              !onBuyShares && !onSellShares ? 'Shares not wired' : ''
            }
          >
            Shares
          </button>
          {resolveOpen && (
            <button
              className={'pp-tab pp-tab-resolve' + (tab === 'resolve' ? ' on' : '')}
              onClick={() => setTab('resolve')}
              disabled={!onResolveExpired}
              title={
                expiredCount > 1
                  ? `${expiredCount} expired options need to be resolved`
                  : 'Resolve the expired option'
              }
            >
              Resolve
              {expiredCount > 0 && (
                <span className="pp-tab-badge">{expiredCount}</span>
              )}
            </button>
          )}
        </div>

        {/* SIDECAR */}
        <div className="pp-sidecar">
          <div className="pp-form">
            {tab === 'open' && (
              <OpenFields
                form={openForm}
                setForm={setOpenForm}
                spot={position.quantity > 0 ? position.market_value / position.quantity : null}
              />
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
            {tab === 'shares' && (
              <>
                <SharesFields
                  mode={sharesMode}
                  setMode={setSharesMode}
                  form={sellForm}
                  setForm={setSellForm}
                  currentQty={position.quantity}
                  avgCost={position.avg_cost}
                />
                {sharesMode === 'buy' && (
                  <div className="pp-override-row">
                    <label className="pp-override-toggle">
                      <input
                        type="checkbox"
                        checked={overrideAvg}
                        onChange={(e) => setOverrideAvg(e.target.checked)}
                      />
                      Set average cost manually
                      <span className="pp-override-hint">
                        {' '}— useful for FIFO / wash-sale adjustments that don't match weighted avg
                      </span>
                    </label>
                    {overrideAvg && (
                      <div className="pp-override-input-row">
                        <span className="pp-override-input-lbl">New avg $</span>
                        <input
                          type="text"
                          inputMode="decimal"
                          className="pp-override-input"
                          value={overrideAvgInput}
                          onChange={(e) => setOverrideAvgInput(e.target.value)}
                          placeholder={position.avg_cost.toFixed(2)}
                          autoFocus
                        />
                      </div>
                    )}
                  </div>
                )}
              </>
            )}
            {tab === 'resolve' && resolveOpen && (
              <ResolveFields
                form={resolveForm}
                setForm={setResolveForm}
                open={resolveOpen}
                closeAtExpiry={resolveExpiryClose ?? null}
              />
            )}
          </div>

          <aside className="pp-rail">
            {/* One graph-first card up top — Weekly income | Cost toggle.
                Replaces the old POSITION + Risk + Live legs + Activity
                stack which had outgrown the modal height. */}
            <RailGraphCard
              ticker={position.ticker}
              avgCost={position.avg_cost}
              effectiveCost={position.effective_cost}
            />

            <div className="pp-rail-divider" />

            <div className="pp-rail-section">
              <div className="pp-rail-lbl">
                {tab === 'open' ? 'New trade preview'
                  : tab === 'close' ? 'Realized P&L'
                  : tab === 'edit' ? 'Edit preview'
                  : tab === 'shares'
                    ? sharesMode === 'buy' ? 'Buy preview' : 'Sale preview'
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
              {tab === 'shares' && sharesMode === 'sell' && (
                <>
                  <div className={'pp-rail-bignum ' + (sellRealized > 0 ? 'pos' : sellRealized < 0 ? 'neg' : '')}>
                    {sharesQtyN === 0
                      ? '—'
                      : sellRealized >= 0
                        ? fmtUSD(sellRealized)
                        : '−' + fmtUSD(Math.abs(sellRealized))}
                  </div>
                  <div className="pp-rail-sub">
                    {sharesQtyN > 0
                      ? `${sharesQtyN} sh × (${fmtUSD2(sharesPriceN)} − ${fmtUSD2(position.avg_cost)})`
                      : 'enter qty + price'}
                  </div>
                </>
              )}
              {tab === 'shares' && sharesMode === 'buy' && (
                <>
                  <div className="pp-rail-bignum">
                    {sharesQtyN === 0 ? '—' : fmtUSD2(buyNewAvg)}
                  </div>
                  <div className="pp-rail-sub">
                    {sharesQtyN > 0
                      ? (overrideAvg && overrideAvgN > 0
                          ? `manual avg · ${sharesQtyN} sh added → ${buyNewQty} total`
                          : `new avg after buying ${sharesQtyN} sh @ ${fmtUSD2(sharesPriceN)}`)
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
            onClick={requestMarkClosed}
          >
            {isClosed ? '↻ Reopen position' : '✕ Mark position closed'}
          </button>
          <div className="pp-popup-foot-end">
            <button className="pp-btn pp-btn-text" onClick={onClose}>Cancel</button>
            {tab === 'open' && (
              <button className="pp-btn pp-btn-neon" onClick={requestOpen} disabled={!canSubmitOpen}>
                ✓ Open position
              </button>
            )}
            {tab === 'close' && (
              <button className="pp-btn pp-btn-neon" onClick={requestClose} disabled={!canSubmitClose}>
                ✓ Close position
              </button>
            )}
            {tab === 'edit' && (
              <button
                className="pp-btn pp-btn-neon"
                onClick={requestEdit}
                disabled={!canSubmitEdit || !editDirty}
                title={!editDirty ? 'No changes' : ''}
              >
                ✓ Save changes
              </button>
            )}
            {tab === 'shares' && (
              <button
                className="pp-btn pp-btn-neon"
                onClick={requestShares}
                disabled={!canSubmitShares}
              >
                {sharesMode === 'buy' ? '✓ Buy shares' : '✓ Sell shares'}
              </button>
            )}
            {tab === 'resolve' && (
              <button
                className="pp-btn pp-btn-neon"
                onClick={requestResolve}
                disabled={!canSubmitResolve}
              >
                ✓ Resolve
              </button>
            )}
          </div>
        </div>
      </div>
      {/* Confirm overlay — sits on top of the modal stage with its own
          backdrop. Clicking outside or pressing Esc cancels (handled in
          the dialog itself); Enter commits. */}
      {confirm && (
        <ConfirmDialog state={confirm} onCancel={() => setConfirm(null)} />
      )}
    </div>
  );
}

// ───────────────────────── Sub-components

function OpenFields({
  form, setForm, spot,
}: {
  form: OpenForm;
  setForm: (f: OpenForm) => void;
  spot: number | null;
}) {
  const set = <K extends keyof OpenForm>(k: K, v: OpenForm[K]) =>
    setForm({ ...form, [k]: v });

  // Strike-vs-spot annotation. Shows the percentage gap between the
  // entered strike and the live spot price so the user can see at a
  // glance how OTM/ITM the contract is being sold. Direction-aware:
  //   • Short call OR long put → wants strike > spot (OTM is positive)
  //   • Short put  OR long call → wants strike < spot (OTM is negative)
  // We always render the signed % from spot; the tone (otm/itm) flags
  // whether that's "favorable" given the position type + direction.
  const strikeN = parseFloat(form.strike);
  const strikePctFromSpot = (spot && spot > 0 && strikeN > 0)
    ? ((strikeN - spot) / spot) * 100
    : null;
  const isCallish = form.option_type === 'call';
  const isShort   = form.direction === 'short';
  // "Favorable OTM" rules-of-thumb for visual tone:
  //   short call → strike above spot       (positive %)
  //   short put  → strike below spot       (negative %)
  //   long call  → strike below spot       (already ITM-leaning long)
  //   long put   → strike above spot       (already ITM-leaning long)
  const favorableSign =
    (isShort && isCallish)  ? +1 :
    (isShort && !isCallish) ? -1 :
    (!isShort && isCallish) ? -1 :
                              +1;
  const strikeTone =
    strikePctFromSpot == null ? 'neutral'
    : Math.sign(strikePctFromSpot) === favorableSign ? 'otm'
    : 'itm';

  return (
    <>
      {/* Conversational action picker — replaces the original "Option
          type + Direction" pair with one row of four explicit choices:
          "Sell calls", "Buy calls", "Sell puts", "Buy puts". Reads as
          intent rather than as two coupled enums; harder to misclick a
          short for a long. The underlying form still stores option_type
          and direction independently. */}
      <div className="pp-field">
        <div className="pp-field-label">What do you want to do?</div>
        <div className="pp-action-grid">
          {(
            [
              { lbl: 'Sell calls', dir: 'short', opt: 'call', tone: 'sold'   },
              { lbl: 'Buy calls',  dir: 'long',  opt: 'call', tone: 'bought' },
              { lbl: 'Sell puts',  dir: 'short', opt: 'put',  tone: 'sold'   },
              { lbl: 'Buy puts',   dir: 'long',  opt: 'put',  tone: 'bought' },
            ] as const
          ).map((a) => {
            const on = form.option_type === a.opt && form.direction === a.dir;
            return (
              <button
                key={a.lbl}
                type="button"
                className={`pp-action-btn tone-${a.tone}` + (on ? ' on' : '')}
                onClick={() => {
                  // Update both fields in one batch so the rail preview
                  // doesn't flash a transient combo while typing.
                  setForm({ ...form, option_type: a.opt, direction: a.dir });
                }}
              >
                <span className={`pp-action-glyph tone-${a.tone}`}>
                  {a.opt === 'call' ? 'C' : 'P'}
                </span>
                <span className="pp-action-lbl">{a.lbl}</span>
              </button>
            );
          })}
        </div>
      </div>

      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label-row">
            <span className="pp-field-label">Strike</span>
            {spot != null && spot > 0 && (
              <span className="pp-spot-chip">
                <span className="pp-spot-chip-lbl">SPOT</span>
                <span className="pp-spot-chip-val">{fmtUSD2(spot)}</span>
                {strikePctFromSpot != null && (
                  <span className={`pp-spot-chip-diff tone-${strikeTone}`}>
                    {strikePctFromSpot >= 0 ? '+' : ''}{strikePctFromSpot.toFixed(1)}%
                  </span>
                )}
              </span>
            )}
          </div>
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
        <div className="pp-leg-picker" role="radiogroup">
          {liveOpens.map((lo) => (
            <LegPickerCard
              key={lo.open.id}
              trade={lo.open}
              contracts={lo.remaining_contracts}
              isSelected={form.target_id === lo.open.id}
              onSelect={() => set('target_id', lo.open.id)}
              radioName="close-target"
            />
          ))}
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
        <div className="pp-leg-picker" role="radiogroup">
          {opens.map((t) => (
            <LegPickerCard
              key={t.id}
              trade={t}
              contracts={t.contracts}
              isSelected={form?.target_id === t.id}
              onSelect={() => selectTrade(t.id)}
              radioName="edit-target"
            />
          ))}
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

// ─────────────────── RailGraphCard ──────────────────────────────
// Single rail card with a [Weekly income] / [Cost] toggle. Graph-first;
// numbers are the only supporting text.
//
//   Weekly income view: 12-week bar chart of premium collected from
//   sold legs (calls + puts) on this ticker. Premium counts on the
//   trade_date of each short-open; closes that returned premium are
//   netted out from the week they closed in. Hero = last 7-day total.
//
//   Cost view: avg cost vs effective cost as two side-by-side bars
//   (taller = higher dollars). Hero = % reduction (positive = options
//   activity has paid down the basis; negative = you've paid more in
//   premium than you've taken back).
//
// Data source: option_trades filtered to this ticker. One query;
// cached by ticker so re-opening the modal is instant.

type GraphView = 'income' | 'cost';

function RailGraphCard({
  ticker, avgCost, effectiveCost,
}: {
  ticker: string;
  avgCost: number;
  effectiveCost: number;
}) {
  const [view, setView] = useState<GraphView>('income');

  // Per-ticker trade pull. Same option_trades table the rest of the
  // module uses; cached separately from the global trades list so this
  // modal doesn't have to wait for the (much bigger) full pull.
  const { data: trades = [] } = useQuery({
    queryKey: ['option_trades_for_ticker', ticker],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('option_trades' as never)
        .select('*')
        .eq('ticker', ticker)
        .order('trade_date', { ascending: true });
      if (error) throw error;
      return (data ?? []) as unknown as OptionTrade[];
    },
  });

  return (
    <div className="pp-railcard">
      {/* Toggle strip — pill style like the example */}
      <div className="pp-railcard-toggle" role="tablist">
        <button
          role="tab"
          className={'pp-railcard-toggle-btn' + (view === 'income' ? ' on' : '')}
          onClick={() => setView('income')}
        >
          Weekly income
        </button>
        <button
          role="tab"
          className={'pp-railcard-toggle-btn' + (view === 'cost' ? ' on' : '')}
          onClick={() => setView('cost')}
        >
          Cost
        </button>
      </div>

      {view === 'income'
        ? <WeeklyIncomeView trades={trades} />
        : <CostView avgCost={avgCost} effectiveCost={effectiveCost} />}
    </div>
  );
}

/** 12 weeks of premium income. Premium collected = short opens; closing
 *  costs (buying back the short) net against the close week. */
function WeeklyIncomeView({ trades }: { trades: OptionTrade[] }) {
  const WEEKS = 12;
  // Buckets: an array of {weekStartIso, premium} for the last WEEKS
  // weeks (oldest first). "Week" = 7-day window aligned to today.
  const buckets = useMemo(() => {
    const today = new Date();
    // Anchor to the start of today (UTC) so bucket math doesn't drift
    // by hours of the day the user opens the modal.
    today.setUTCHours(0, 0, 0, 0);
    const out: Array<{ start: Date; label: string; dollars: number }> = [];
    for (let i = WEEKS - 1; i >= 0; i--) {
      const start = new Date(today);
      start.setUTCDate(start.getUTCDate() - (i + 1) * 7 + 1);
      const label = `${start.getUTCMonth() + 1}/${start.getUTCDate()}`;
      out.push({ start, label, dollars: 0 });
    }
    // Bucket a trade into a week. Short opens add premium; closes net
    // against the week the close happened.
    for (const t of trades) {
      const dt = new Date(t.trade_date + 'T00:00:00Z');
      const diffDays = Math.floor((today.getTime() - dt.getTime()) / 86400000);
      const weekIdx = WEEKS - 1 - Math.floor(diffDays / 7);
      if (weekIdx < 0 || weekIdx >= WEEKS) continue;
      const dollars = t.contracts * 100 * t.premium;
      if (t.action === 'open' && t.direction === 'short') {
        out[weekIdx].dollars += dollars;             // premium IN
      } else if (t.action === 'close' && t.direction === 'short') {
        out[weekIdx].dollars -= dollars;             // bought back, premium OUT
      }
      // (Long opens/closes are excluded — they're costs, not income.)
    }
    return out;
  }, [trades]);

  const lastWeek = buckets[buckets.length - 1]?.dollars ?? 0;
  const total = buckets.reduce((s, b) => s + b.dollars, 0);
  const avg = total / WEEKS;
  const max = Math.max(1, ...buckets.map((b) => Math.abs(b.dollars)));

  return (
    <>
      <div className="pp-railcard-hero">
        <div className="pp-railcard-lbl">Last 7 days</div>
        <div className={'pp-railcard-num ' + (lastWeek > 0 ? 'pos' : lastWeek < 0 ? 'neg' : '')}>
          {lastWeek === 0 ? '$0'
            : lastWeek > 0 ? fmtUSD(lastWeek)
            : '−' + fmtUSD(Math.abs(lastWeek))}
        </div>
      </div>

      {/* 12-week bar chart — CSS heights, no chart lib needed.
          Positive = neon, negative = red. Min 2px so empty weeks still
          draw a baseline tick. */}
      <div className="pp-railcard-bars">
        {buckets.map((b, i) => {
          const heightPct = Math.max(2, (Math.abs(b.dollars) / max) * 100);
          const tone = b.dollars > 0 ? 'pos' : b.dollars < 0 ? 'neg' : 'zero';
          return (
            <div key={i} className="pp-railcard-bar-col" title={`${b.label}: ${b.dollars >= 0 ? fmtUSD(b.dollars) : '−' + fmtUSD(Math.abs(b.dollars))}`}>
              <div className={`pp-railcard-bar tone-${tone}`} style={{ height: `${heightPct}%` }} />
            </div>
          );
        })}
      </div>

      <div className="pp-railcard-rows">
        <div className="pp-railcard-row">
          <span className="k">12-wk total</span>
          <span className={'v ' + (total > 0 ? 'pos' : total < 0 ? 'neg' : '')}>
            {total >= 0 ? fmtUSD(total) : '−' + fmtUSD(Math.abs(total))}
          </span>
        </div>
        <div className="pp-railcard-row">
          <span className="k">Avg / week</span>
          <span className="v">{avg >= 0 ? fmtUSD(avg) : '−' + fmtUSD(Math.abs(avg))}</span>
        </div>
      </div>
    </>
  );
}

/** Avg cost vs effective cost as two bars. Effective cost = avg cost
 *  minus net options cash per share (already computed upstream). */
function CostView({
  avgCost, effectiveCost,
}: {
  avgCost: number; effectiveCost: number;
}) {
  // Percentage reduction — positive means options activity has paid
  // down the basis; negative means premium outlays raised it.
  const reductionPct = avgCost > 0
    ? ((avgCost - effectiveCost) / avgCost) * 100
    : 0;
  const reductionTone = reductionPct > 0 ? 'pos' : reductionPct < 0 ? 'neg' : '';
  // Bars: tallest equals max value so the comparison is honest.
  const maxVal = Math.max(avgCost, effectiveCost) || 1;
  const avgHeight = (avgCost / maxVal) * 100;
  const effHeight = (effectiveCost / maxVal) * 100;

  return (
    <>
      <div className="pp-railcard-hero">
        <div className="pp-railcard-lbl">Net vs avg</div>
        <div className={'pp-railcard-num ' + reductionTone}>
          {reductionPct > 0 ? '−' : reductionPct < 0 ? '+' : ''}{Math.abs(reductionPct).toFixed(1)}%
        </div>
      </div>

      {/* Two side-by-side vertical bars. Heights scaled to max($avg, $eff). */}
      <div className="pp-railcard-costbars">
        <div className="pp-railcard-costcol">
          <div className="pp-railcard-costbar tone-avg" style={{ height: `${avgHeight}%` }}>
            <span className="pp-railcard-costbar-val">{fmtUSD2(avgCost)}</span>
          </div>
          <div className="pp-railcard-costcol-lbl">AVG</div>
        </div>
        <div className="pp-railcard-costcol">
          <div className={`pp-railcard-costbar tone-eff ${reductionTone}`} style={{ height: `${effHeight}%` }}>
            <span className="pp-railcard-costbar-val">{fmtUSD2(effectiveCost)}</span>
          </div>
          <div className="pp-railcard-costcol-lbl">NET</div>
        </div>
      </div>

      <div className="pp-railcard-rows">
        <div className="pp-railcard-row">
          <span className="k">Premium impact / sh</span>
          <span className={'v ' + reductionTone}>
            {reductionPct > 0 ? '−' : '+'}{fmtUSD2(Math.abs(avgCost - effectiveCost))}
          </span>
        </div>
      </div>
    </>
  );
}

/** Human label for a leg given its direction + type — used in the
 *  picker card title chip and the Live-legs rail cards.
 *
 *   short call → "CALLS SOLD"    (premium collected, capped upside)
 *   short put  → "PUTS SOLD"     (premium collected, assignment risk)
 *   long  call → "CALLS BOUGHT"  (premium paid, levered upside)
 *   long  put  → "PUTS BOUGHT"   (premium paid, downside protection)
 *
 *  Plural form reads naturally on cards that represent 1+ contracts.
 *  Singular still works grammatically ("1 contract · CALLS SOLD"). */
function legActionLabel(direction: Direction, optionType: OptionType): string {
  const kind = optionType === 'call' ? 'CALLS' : 'PUTS';
  const verb = direction === 'short' ? 'SOLD' : 'BOUGHT';
  return `${kind} ${verb}`;
}

/** Direction tone — drives the left-edge accent on cards. Short legs
 *  generated premium (green); long legs cost premium (amber). Distinct
 *  from ITM/OTM tone which we keep on a separate badge. */
function legDirTone(direction: Direction): 'sold' | 'bought' {
  return direction === 'short' ? 'sold' : 'bought';
}

/** Picker card body — used in CloseFields + EditFields. One card per
 *  selectable leg. Side accent reflects direction; title chip names the
 *  action class; the hero is the strike + contract count so the user
 *  can spot the leg at a glance. */
function LegPickerCard({
  trade, contracts, isSelected, onSelect, radioName,
}: {
  trade: OptionTrade;
  contracts: number;                    // remaining (close) or original (edit)
  isSelected: boolean;
  onSelect: () => void;
  radioName: string;
}) {
  const tone = legDirTone(trade.direction);
  const title = legActionLabel(trade.direction, trade.option_type);
  return (
    <label className={`pp-leg-card pp-leg-card-${tone}` + (isSelected ? ' on' : '')}>
      <input
        type="radio"
        name={radioName}
        value={trade.id}
        checked={isSelected}
        onChange={onSelect}
        className="pp-leg-card-radio"
      />
      <span className="pp-leg-card-dot" aria-hidden />
      <span className={`pp-leg-card-glyph tone-${tone}`}>
        {trade.option_type === 'put' ? 'P' : 'C'}
      </span>
      <div className="pp-leg-card-body">
        <div className="pp-leg-card-row1">
          <span className="pp-leg-card-strike">{fmtUSD2(trade.strike)}</span>
          <span className={`pp-leg-card-title tone-${tone}`}>{title}</span>
        </div>
        <div className="pp-leg-card-row2">
          {contracts} {contracts === 1 ? 'contract' : 'contracts'}
          {' '}· @ ${trade.premium}/sh
          {' '}· exp {trade.expiry}
        </div>
      </div>
    </label>
  );
}

/** Right-rail card — one per live leg. Same visual idiom as the picker
 *  (left edge tone, P/C glyph, title chip, strike hero) but richer:
 *  it adds %-from-spot, a days-to-expiry chip with color thresholds,
 *  break-even, premium per share, and contract count.
 *
 *  Calculations:
 *   • % from spot — (strike − spot) / spot. Tone: OTM-favourable green,
 *     ITM-leaning red. The favourable side is direction-aware (short
 *     calls want strike > spot, short puts want strike < spot, etc.).
 *   • Break-even — short call: strike + premium · short put: strike −
 *     premium · long call: strike + premium · long put: strike − premium.
 *   • Days to expiry — calendar days between today and expiry.
 *     <7d → red, <30d → amber, otherwise neutral.  */
function LiveLegCard({
  leg, spot,
}: {
  leg: LiveOption;
  spot: number | null;
}) {
  const o = leg.open;
  const tone = legDirTone(o.direction);
  const title = legActionLabel(o.direction, o.option_type);
  const isCall = o.option_type === 'call';
  const isShort = o.direction === 'short';

  // % from spot — sign + color
  const pctFromSpot = (spot && spot > 0) ? ((o.strike - spot) / spot) * 100 : null;
  const favorableSign =
    (isShort && isCall)   ? +1 :
    (isShort && !isCall)  ? -1 :
    (!isShort && isCall)  ? -1 :
                            +1;
  const spotTone =
    pctFromSpot == null ? 'neutral'
    : Math.sign(pctFromSpot) === favorableSign ? 'otm'
    : 'itm';

  // Break-even — direction × type matrix
  const breakEven =
    isCall ? o.strike + o.premium
           : o.strike - o.premium;

  // Days to expiry — calendar days; color thresholds bucket the chip.
  const today = new Date();
  const exp = new Date(o.expiry + 'T00:00:00Z');
  const dte = Math.max(0, Math.round((exp.getTime() - today.getTime()) / 86400000));
  const dteTone = dte < 7 ? 'urgent' : dte < 30 ? 'soon' : 'normal';

  return (
    <div className={`pp-livecard pp-livecard-${tone}`}>
      <div className="pp-livecard-head">
        <span className={`pp-leg-card-glyph tone-${tone}`}>
          {isCall ? 'C' : 'P'}
        </span>
        <span className={`pp-leg-card-title tone-${tone}`}>{title}</span>
      </div>
      <div className="pp-livecard-hero">
        <div className="pp-livecard-strike">{fmtUSD2(o.strike)}</div>
        {pctFromSpot != null && (
          <div className={`pp-livecard-spotdiff tone-${spotTone}`}>
            {pctFromSpot >= 0 ? '+' : ''}{pctFromSpot.toFixed(1)}% from spot
          </div>
        )}
      </div>
      <div className="pp-livecard-rows">
        <div className="pp-livecard-row">
          <span className="k">Premium</span>
          <span className="v">{fmtUSD2(o.premium)} / sh</span>
        </div>
        <div className="pp-livecard-row">
          <span className="k">Break-even</span>
          <span className="v">{fmtUSD2(breakEven)}</span>
        </div>
        <div className="pp-livecard-row">
          <span className="k">Days to exp</span>
          <span className={`v pp-livecard-dtechip tone-${dteTone}`}>{dte}d</span>
        </div>
        <div className="pp-livecard-row">
          <span className="k">Contracts</span>
          <span className="v">{leg.remaining_contracts}</span>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── §4 — Risk flags ─────────────────────────────
// Surfaces the most common "you should look at this" conditions across
// the live legs. Three categories today, room to add more without
// touching the card layout:
//   • Assignment risk — short leg, ITM, <14d to expiry
//   • Expiring soon — any leg with <7d to expiry (regardless of ITM)
//   • Stale — leg whose expiry has already passed (needs Resolve)
//
// Each flag has a tone (red = urgent, amber = soon, blue = info) which
// drives the colored dot in the card list.

type RiskTone = 'urgent' | 'soon' | 'info';
interface RiskFlag {
  tone: RiskTone;
  label: string;      // top line — "Assignment risk", "Expiring soon"
  detail: string;     // sub line — "$625 call · ITM · 4d"
}

function computeRiskFlags(legs: LiveOption[], spot: number | null): RiskFlag[] {
  const out: RiskFlag[] = [];
  const today = new Date();

  for (const leg of legs) {
    const o = leg.open;
    const expDate = new Date(o.expiry + 'T00:00:00Z');
    const dte = Math.round((expDate.getTime() - today.getTime()) / 86400000);
    const desc = `${o.contracts} ${o.direction} ${o.option_type} · ${fmtUSD2(o.strike)}`;

    // Stale: expired, still un-resolved.
    if (dte < 0) {
      out.push({
        tone: 'urgent',
        label: 'Expired — needs Resolve',
        detail: `${desc} · ${Math.abs(dte)}d past`,
      });
      continue;     // skip the other checks for stale legs
    }

    // Assignment risk: short leg, ITM, near expiry.
    if (o.direction === 'short' && spot != null && dte <= 14) {
      const itm = (o.option_type === 'call' && spot >= o.strike)
               || (o.option_type === 'put'  && spot <= o.strike);
      if (itm) {
        out.push({
          tone: 'urgent',
          label: 'Assignment risk',
          detail: `${desc} · ITM · ${dte}d to exp`,
        });
        continue;
      }
    }

    // Expiring soon: any leg <7d, not already flagged as assignment risk.
    if (dte <= 7) {
      out.push({
        tone: 'soon',
        label: 'Expiring this week',
        detail: `${desc} · ${dte}d to exp`,
      });
    }
  }

  return out;
}

function RiskCard({ flags }: { flags: RiskFlag[] }) {
  // Hero number is the flag count; tone of the hero matches the most
  // urgent flag in the list (red beats amber beats blue) so the eye
  // catches "something needs action" before reading the list.
  const heroTone = flags.some((f) => f.tone === 'urgent') ? 'urgent'
                 : flags.some((f) => f.tone === 'soon')    ? 'soon'
                 : 'info';
  return (
    <div className={`pp-rail-section pp-riskcard tone-${heroTone}`}>
      <div className="pp-rail-lbl">Risk check</div>
      <div className={`pp-riskcard-hero tone-${heroTone}`}>{flags.length}</div>
      <div className="pp-riskcard-sub">
        {flags.length === 1 ? 'active flag' : 'active flags'}
      </div>
      <ul className="pp-riskcard-list">
        {flags.map((f, i) => (
          <li key={i} className={`pp-riskcard-item tone-${f.tone}`}>
            <span className="pp-riskcard-dot" aria-hidden />
            <div className="pp-riskcard-text">
              <div className="pp-riskcard-label">{f.label}</div>
              <div className="pp-riskcard-detail">{f.detail}</div>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

// ─────────────────── §5 — Activity card ──────────────────────────
// Right-rail card surfacing "how active is this position?" — driven by
// the live-leg roster + the position's net options cash. We don't
// receive the full trade history in props, so the hero metric is
// "active since" (the earliest live leg's open date). Sparkline of
// cumulative realized is parked for a later pass when we wire the full
// trade history through.

function ActivityCard({
  liveOpens, netOptionsCash,
}: {
  liveOpens: LiveOption[];
  netOptionsCash: number;
}) {
  // Earliest open date across all live legs (proxy for "active since"
  // when we don't have the closed-trade history). Sorted ascending so
  // the first entry is the oldest.
  const sortedByDate = [...liveOpens].sort(
    (a, b) => a.open.trade_date.localeCompare(b.open.trade_date),
  );
  const earliest = sortedByDate[0]?.open.trade_date;
  const today = new Date();
  const earliestDate = earliest ? new Date(earliest + 'T00:00:00Z') : null;
  const daysActive = earliestDate
    ? Math.max(0, Math.round((today.getTime() - earliestDate.getTime()) / 86400000))
    : 0;

  // Pick the right unit for the hero: days for <60, months for <365,
  // years above that. Keeps the number short + scannable.
  let heroValue: string;
  let heroUnit: string;
  if (daysActive < 60) {
    heroValue = String(daysActive);
    heroUnit = daysActive === 1 ? 'day' : 'days';
  } else if (daysActive < 365) {
    heroValue = String(Math.round(daysActive / 30));
    heroUnit = 'months';
  } else {
    const years = daysActive / 365;
    heroValue = years.toFixed(1);
    heroUnit = 'years';
  }

  // Soonest + latest expiry across live legs.
  const sortedByExpiry = [...liveOpens].sort(
    (a, b) => a.open.expiry.localeCompare(b.open.expiry),
  );
  const soonestExp = sortedByExpiry[0]?.open.expiry;
  const latestExp = sortedByExpiry[sortedByExpiry.length - 1]?.open.expiry;
  const dteFor = (iso: string | undefined) =>
    iso ? Math.max(0, Math.round((new Date(iso + 'T00:00:00Z').getTime() - today.getTime()) / 86400000)) : 0;

  return (
    <div className="pp-rail-section pp-activitycard">
      <div className="pp-rail-lbl">Active since</div>
      <div className="pp-activitycard-hero">
        {heroValue}<span className="pp-activitycard-unit">{heroUnit}</span>
      </div>
      <div className="pp-activitycard-sub">
        {earliest ? fmtDateHuman(earliest) : 'no live legs'}
      </div>
      <div className="pp-activitycard-rows">
        <div className="pp-activitycard-row">
          <span className="k">Live legs</span>
          <span className="v">{liveOpens.length}</span>
        </div>
        <div className="pp-activitycard-row">
          <span className="k">Soonest exp</span>
          <span className="v">{dteFor(soonestExp)}d</span>
        </div>
        <div className="pp-activitycard-row">
          <span className="k">Latest exp</span>
          <span className="v">{dteFor(latestExp)}d</span>
        </div>
        <div className="pp-activitycard-row">
          <span className="k">Net option cash</span>
          <span className={`v ${netOptionsCash >= 0 ? 'pos' : 'neg'}`}>
            {netOptionsCash >= 0 ? fmtUSD(netOptionsCash) : '−' + fmtUSD(Math.abs(netOptionsCash))}
          </span>
        </div>
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

// ─────────────────────────────────────────────────────────────────────
// Shares fields — Buy / Sell toggle inside; same qty/price/date inputs.
function SharesFields({
  mode, setMode, form, setForm, currentQty, avgCost,
}: {
  mode: 'buy' | 'sell';
  setMode: (m: 'buy' | 'sell') => void;
  form: SellForm;
  setForm: (f: SellForm) => void;
  currentQty: number;
  avgCost: number;
}) {
  const set = <K extends keyof SellForm>(k: K, v: SellForm[K]) =>
    setForm({ ...form, [k]: v });
  const sellMax = currentQty;
  return (
    <>
      <div className="pp-field">
        <div className="pp-field-label">Action</div>
        <div className="pp-source-seg">
          <button
            type="button"
            className={'pp-source-opt' + (mode === 'buy' ? ' on' : '')}
            onClick={() => setMode('buy')}
          >
            <span className="pp-glyph-tile">+</span>
            <span>Buy shares</span>
          </button>
          <button
            type="button"
            className={'pp-source-opt' + (mode === 'sell' ? ' on' : '') + (sellMax === 0 ? ' disabled' : '')}
            onClick={() => sellMax > 0 && setMode('sell')}
            disabled={sellMax === 0}
            title={sellMax === 0 ? 'No shares on hand' : ''}
          >
            <span className="pp-glyph-tile">−</span>
            <span>Sell shares</span>
          </button>
        </div>
      </div>

      <div className="pp-form-grid cols-2">
        <div className="pp-field">
          <div className="pp-field-label">Quantity</div>
          <input
            className="pp-input mono"
            type="number"
            min="1"
            max={mode === 'sell' ? sellMax : undefined}
            step="1"
            value={form.quantity}
            onChange={(e) => set('quantity', e.target.value)}
            placeholder={mode === 'sell' ? String(sellMax) : 'shares to buy'}
          />
          <div className="pp-field-hint">
            {mode === 'sell'
              ? `up to ${fmtQty(sellMax)} on hand`
              : `current ${fmtQty(currentQty)} on hand`}
          </div>
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
  form, setForm, open, closeAtExpiry,
}: {
  form: ResolveForm;
  setForm: (f: ResolveForm) => void;
  open: OptionTrade;
  closeAtExpiry: number | null;
}) {
  const set = <K extends keyof ResolveForm>(k: K, v: ResolveForm[K]) =>
    setForm({ ...form, [k]: v });
  const isCall = open.option_type === 'call';
  // ITM hint based on the snapshot close (when we have it).
  const itmHint = (() => {
    if (closeAtExpiry == null) {
      return {
        text: 'No close snapshot for this expiry — pick manually.',
        tone: 'muted' as const,
      };
    }
    const itm = isCall
      ? closeAtExpiry >= open.strike
      : closeAtExpiry <= open.strike;
    if (itm) {
      const dist = isCall
        ? closeAtExpiry - open.strike
        : open.strike - closeAtExpiry;
      return {
        text: `Close ${fmtUSD2(closeAtExpiry)} vs strike ${fmtUSD2(open.strike)} — ITM by ${fmtUSD2(dist)}, suggesting Exercised`,
        tone: 'itm' as const,
      };
    }
    const dist = isCall
      ? open.strike - closeAtExpiry
      : closeAtExpiry - open.strike;
    return {
      text: `Close ${fmtUSD2(closeAtExpiry)} vs strike ${fmtUSD2(open.strike)} — OTM by ${fmtUSD2(dist)}, suggesting Expired worthless`,
      tone: 'otm' as const,
    };
  })();
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
        <div className={'pp-resolve-hint ' + itmHint.tone}>{itmHint.text}</div>
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

// ─────────────────── Confirm dialog (shared by all submit actions)
//
// One overlay component reused by Open / Close / Edit / Shares / Resolve
// / Mark-closed. Each request* helper in the modal builds a ConfirmState
// describing the action in plain English; this dialog renders it on top
// of the modal so the user can verify the ticker + numbers before
// committing. The big neon ticker is the specific guardrail against
// "I meant META but I was on WDAY" mistakes.

interface ConfirmLine {
  label: string;
  value: React.ReactNode;
  /** Tone informs color: positive (green), negative (red), emphasis
   *  (bright), normal (default). Used sparingly on totals / P&L. */
  tone?: 'normal' | 'positive' | 'negative' | 'emphasis';
}

interface ConfirmState {
  ticker: string;
  title: string;             // small caps header — "Confirm open" etc.
  heading: string;           // plain-English sentence — "Selling 10 short calls"
  lines: ConfirmLine[];
  confirmLabel: string;      // text for the Confirm button
  /** Neutral by default; danger uses red accent (only used by mark-closed). */
  tone?: 'neutral' | 'danger';
  /** What to do when the user clicks Confirm. */
  action: () => void;
}

function ConfirmDialog({
  state, onCancel,
}: {
  state: ConfirmState;
  onCancel: () => void;
}) {
  // Esc cancels, Enter confirms. The handler stops propagation so the
  // outer modal's Esc handler doesn't also fire and close everything.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onCancel();
      } else if (e.key === 'Enter') {
        e.stopPropagation();
        state.action();
      }
    };
    window.addEventListener('keydown', onKey, true);   // capture phase
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onCancel, state]);

  return (
    <div className="pp-confirm-stage" onClick={onCancel}>
      <div
        className={'pp-confirm-card' + (state.tone === 'danger' ? ' danger' : '')}
        role="alertdialog"
        aria-modal="true"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="pp-confirm-title">{state.title}</div>
        <div className="pp-confirm-ticker">{state.ticker}</div>
        <div className="pp-confirm-heading">{state.heading}</div>
        <ul className="pp-confirm-lines">
          {state.lines.map((l, i) => (
            <li key={i} className={`pp-confirm-line tone-${l.tone ?? 'normal'}`}>
              <span className="k">{l.label}</span>
              <span className="v">{l.value}</span>
            </li>
          ))}
        </ul>
        <div className="pp-confirm-foot">
          <button className="pp-btn pp-btn-text" onClick={onCancel}>Cancel</button>
          <button
            className={'pp-btn pp-btn-neon' + (state.tone === 'danger' ? ' danger' : '')}
            onClick={() => state.action()}
            autoFocus
          >
            ✓ {state.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

/** Format an ISO date (YYYY-MM-DD) as "May 29, 2026". Returns '—' for
 *  empty input so the confirm dialog stays readable when a date field
 *  hasn't been touched. */
function fmtDateHuman(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso + 'T00:00:00Z');
  if (Number.isNaN(d.getTime())) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}
