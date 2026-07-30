# Sunnyfi P&L Glossary — the single source of truth

**This is governance. These names and formulas are FINAL. Every screen, number,
and label must use these definitions. Do not reinterpret "realized" or
"unrealized" — use exactly what is written here.**

Owner: Niket. Established 2026-07-28 to end the recurring re-derivation.

Scope: NVDA only, across **all** positions (shares + every option leg).

---

## The metrics

### 1. REALIZED
Only **closed** positions. Nothing open. Paper never counts.

```
REALIZED = Stock_Sold_Price − Stock_Buy_Price
         + Premium_Collected_On_Closed_Positions
         − Cost_On_Closed_Positions
         + Dividends_Received_On_Closed_Positions
```

Includes: exercised assignments (treated as closed), sold shares, expired options.

### 2. UNREALIZED
Only **open** positions. Paper only.

```
UNREALIZED = (Current_Price − Buy_Price) × Shares_Held
           − Current_Value_Of_Open_Short_Options
           + (Current_Value_Of_Open_Long_Options − Long_Option_Cost_Basis)
```

### 3. NET
Total P&L across everything (the position today).

```
NET = REALIZED + UNREALIZED
```

### 4. PREMIUM COLLECTED
Money received from **selling** options (calls sold + puts sold).

```
PREMIUM_REALIZED   = premium from sold options that have EXPIRED or been CLOSED (net of buybacks)
PREMIUM_UNREALIZED = premium from sold options STILL OPEN
PREMIUM_TOTAL      = PREMIUM_REALIZED + PREMIUM_UNREALIZED
```

### 5. COST (hedge cost)
Money paid for **buying** options (calls bought + puts bought).

```
COST_REALIZED   = cost of bought options that have EXPIRED or been SOLD
COST_UNREALIZED = cost of bought options STILL OPEN
COST_TOTAL      = COST_REALIZED + COST_UNREALIZED
```

---

## Rules

- **Exercised = REALIZED** (position closed).
- **Expired options = REALIZED** (transaction complete).
- **Assigned short call → premium is NOT re-realized on the option.** When a short
  call is assigned, the shares are sold *at the strike* and that stock sale carries
  the realized P&L (IBKR's convention — matches its `fifoPnlRealized`). Counting the
  assigned call's premium *again* on the option side double-books it. So REALIZED
  and PREMIUM_REALIZED **exclude** the premium of assigned-away calls. (Detection:
  a ≈$0 short-call close with a same-day share sell at the strike — an *expiry*,
  which keeps its premium, has no such share sale.) Established 2026-07-30 during
  the IBKR reconciliation; see [[project_realized_pnl_reconcile]].
- **Open = UNREALIZED** (nothing else). Nothing open is ever in REALIZED.
- **Options SOLD = PREMIUM** (calls sold + puts sold).
- **Options BOUGHT = COST** (calls bought + puts bought).
- Premium received but option still open → **PREMIUM_UNREALIZED**.
- Option bought but still holding → **COST_UNREALIZED**.

---

## Implementation notes (how the code computes each term — no ambiguity)

A leg is **CLOSED** when its net contracts reached 0 (bought/sold back) **or** it
**expired** (expiry date < today). Otherwise it is **OPEN**. Per option key
`(side, kind, strike, expiry)` we track `openCt`, `closeCt`, `openPrem` (Σ open
premium ×ct×100), `closePrem` (Σ close premium ×ct×100), `netCt = openCt − closeCt`,
and `avgOpen` = openPrem / (openCt) per contract.

- `Stock_Sold_Price − Stock_Buy_Price` = **Σ `nvda_share_sells.realized_pl`** (FIFO reconciled).
- **Premium_Collected_On_Closed_Positions** (short legs): for the bought-back
  portion `closeCt·avgOpen − closePrem`; plus, if the leg **expired**, the still-net
  contracts are kept in full: `netCt·avgOpen`.
- **Cost_On_Closed_Positions / long realized** (long legs): for the sold portion
  `closePrem − closeCt·avgOpen` (proceeds − cost); if the leg **expired** worthless,
  `− netCt·avgOpen` (cost lost). (The spec's "− Cost_On_Closed" is the expiry case;
  a long sold for a gain also credits its proceeds.)
- **Dividends_Received_On_Closed** = booked dividend cash (0 until a dividend pays).
- **(Current_Price − Buy_Price) × Shares_Held** = `(spot − avgBuy) × sharesHeld`.
- **Current_Value_Of_Open_Short_Options** = Σ open shorts `mark · netCt · 100` (cost to close; subtracted).
- **Current_Value_Of_Open_Long_Options** = Σ open longs `mark · netCt · 100`.
- **Long_Option_Cost_Basis** (open) = Σ open longs `netCt · avgOpen`.
- **PREMIUM_REALIZED** = the short-leg realized term above (closed + expired shorts).
- **PREMIUM_UNREALIZED** = Σ open shorts `netCt · avgOpen` (premium collected on still-open shorts).
- **COST_REALIZED** = cost basis of closed/expired longs `closeCt·avgOpen (+ expired netCt·avgOpen)`.
- **COST_UNREALIZED** = Σ open longs `netCt · avgOpen`.

Note: PREMIUM and COST are **breakdowns / separate views**, not extra addends to
NET. NET is only REALIZED + UNREALIZED. Per this spec, premium collected on an
OPEN short is **not** in UNREALIZED (only its current mark is, as a liability); it
lives in PREMIUM_UNREALIZED.

## Where each metric shows
- **Portfolio (§1)** — the position today: UNREALIZED (+ its share/short/long parts) is the live number; NET available.
- **How it has performed (§2)** — REALIZED is the hero (closed only). PREMIUM_TOTAL (with the realized/open split) and COST_TOTAL shown as breakdowns.
- **Historical performance (§5)** — REALIZED booked per session (a realizing event on its date).
- Code: `NvPnL` + `NvDerive.pnl(...)` in `NvdaModels.swift` is the ONE implementation; screens read its named fields.
