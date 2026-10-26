"""Named strategies across windows: returns on LEAP capital, calls' share,
drawdown, and how much of a rally was kept versus the LEAP alone."""
import sys, os, json
from combo import score

NAMED = [
    ("No calls (LEAP only)",          "atm", 0.0),
    ("A: 30% ATM + 20% at 1 SD (50%)",  "split_sd1", 0.5),
    ("A: 30% ATM + 30% at 1 SD (60%)",  "split_sd1", 0.6),
    ("B: 2% OTM on 70%",                "otm2", 0.7),
    ("B: 3% OTM on 70%",                "otm3", 0.7),
    ("ATM on 50%",                      "atm", 0.5),
    ("3% OTM on 50%",                   "otm3", 0.5),
    ("5% OTM on 50%",                   "otm5", 0.5),
    ("0.30 delta on 50%",               "d30", 0.5),
    ("0.30 delta on 60%",               "d30", 0.6),
    ("1 SD on 60%",                     "sd1", 0.6),
]

def table(t, leap, freq, fr, to, label):
    print(f"\n{label}: {t} {fr} to {to}, LEAP {leap}, {freq}")
    print(f"  {'strategy':34} {'return':>7} {'calls $':>9} {'LEAP $':>9} {'worst wk':>9} {'drawdown':>9}")
    for name, rule, cov in NAMED:
        s = score(t, leap, freq, rule, cov, fr, to)
        print(f"  {name:34} {s['ret']:+6.0f}% {s['calls']:+9,.0f} {s['leap']:+9,.0f} {s['worst']:+9,.0f} {s['dd']:+9,.0f}")

if __name__ == "__main__":
    t, freq = sys.argv[1], sys.argv[2]
    for w in json.loads(sys.argv[3]):
        for leap in w.get("leaps", ["atm", "d75", "d90"]):
            table(t, leap, freq, w["fr"], w["to"], w["label"])
