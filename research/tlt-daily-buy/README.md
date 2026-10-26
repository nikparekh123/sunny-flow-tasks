# 100 TLT shares a day vs one block (Nik, 7 Oct 2026)

`daily_vs_block.py`: 15,000 shares either at once or 100/day over 150 trading days.
Every start day Apr 2007 to 2026 (real closes + dividends, margin 3.03%), then
forward Monte Carlo from 76.92 at today's 5.04% dividend.

- History: daily ended ahead in 49% of 4,761 windows (median -$2k). It won 90%
  of the time when TLT fell >3% in the window, 7% when it rose >3%. 2020-26
  (rising rates) flatters it: 70% ahead; 2007-20: 41%.
- Forward: calm -$6k (carry on fewer shares), Fed eases -$56k, QE -$102k,
  inflation +$50k. Daily buying is a bet against TLT during the build; it
  narrows regret, not cost.

## Round 2 (split_dips.py): split and down-day buying, judged at day 252
- 10k now + 100/day is closest to the block (median -$1k history, -$6k under
  Fed eases). Down-day rules don't lower the average: 200 on any down day ~= 100 a
  day; 300 on the 2nd red day finishes later and is a bigger bet against TLT
  (-$76k Fed eases, +$67k inflation).
