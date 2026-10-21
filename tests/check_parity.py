# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Compare what MT5 drew (DumpIndicator CSVs of DivergenceSignalAlerts) with tests/reference.py, bar by bar.

    python3 tests/check_parity.py <dump dir>   (needs numpy and pandas; the CSVs are in <dump dir>/dump/ or <dump dir>)
    python3 tests/check_parity.py <dump dir> --mt4      (the MT4 edition, dumps from the MT4 tester)

Buffers: b0 bullish arrow, b1 bearish arrow, b2/b3 their type (1 regular, 2 hidden), b4 RSI, b5 MACD histogram.
The indicator scans the last InpHistory closed bars (start = bars - 1 - history) and never the forming bar.
Pass: RSI and MACD within 1e-9 relative on every scanned bar, and the same arrows of the same type on the same bars."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from reference import Params, run  # noqa: E402

# tag: (Params, history, configs.tsv overrides)
CONFIGS = {
    "dv_default": (Params(), 2000),
    "dv_hidden_both": (Params(hidden=True, min_count=2), 2000),
    "dv_rsi_noclean": (Params(use=(True, False), clean=False, left=3, right=2, max_dist=40), 3000),
}


def num(col):
    return pd.to_numeric(col, errors="coerce").to_numpy(float)


def check(csv: Path, pr: Params, hist: int, mt4=False):
    d = pd.read_csv(csv)
    n = len(d)
    start = max(0, n - 1 - hist)
    h, l, c = (d[k].to_numpy(float) for k in ("high", "low", "close"))
    if mt4:   # MT4 tester: the indicator starts InpHistory bars before the bar it was attached on, then keeps feeding;
        # find that bar from the first RSI value (RSI is on in every config) and the reference's RSI warm-up
        _, osc0 = run(h, l, c, pr, 0, n - 1)
        warm = next(k for k, v in enumerate(osc0[0]) if v is not None)
        start = int(np.flatnonzero(~np.isnan(num(d["b4"])))[0]) - warm
    events, osc = run(h, l, c, pr, start, n - 1)
    rng = slice(start, n - 1)
    msgs, ok = [], True
    for b, o, name in (("b4", 0, "RSI"), ("b5", 1, "MACD")):
        if not pr.use[o]:
            continue
        ref = np.array([np.nan if v is None else v for v in osc[o][:n - 1]] + [np.nan])
        mt = num(d[b])
        good = np.isclose(mt[rng], ref[rng], rtol=1e-9, atol=1e-12, equal_nan=True)
        ok &= bool(good.all())
        msgs.append(f"{name} {'OK' if good.all() else f'{(~good).sum()} differ'}")
    for b, tb, dr, name in (("b0", "b2", 1, "bull"), ("b1", "b3", -1, "bear")):
        mt = sorted(int(i) for i in np.flatnonzero(~np.isnan(num(d[b]))) if start <= i < n - 1)
        ref = sorted(k for k, e in events.items() if e["dir"] == dr)
        types_mt = [int(num(d[tb])[i]) for i in mt]
        types_ref = [events[k]["type"] for k in ref]
        same = mt == ref and types_mt == types_ref
        ok &= same
        msgs.append(f"{name} {len(ref):>3} {'OK' if same else f'DIFFER (mt5 {len(mt)})'}")
        if not same:
            extra, missing = sorted(set(mt) - set(ref))[:5], sorted(set(ref) - set(mt))[:5]
            msgs.append(f"[mt5 only {extra}, ref only {missing}]")
    return ok, f"{csv.stem:38} bars {n:>6} scanned {n - 1 - start:>5}  " + "  ".join(msgs)


if __name__ == "__main__":
    mt4 = "--mt4" in sys.argv
    root = Path([a for a in sys.argv[1:] if a != "--mt4"][0])
    allok, k = True, 0
    for tag, (pr, hist) in CONFIGS.items():
        for f in sorted(root.glob(f"dump/{tag}_*.csv")) + sorted(root.glob(f"{tag}_*.csv")):
            ok, msg = check(f, pr, hist, mt4)
            allok &= ok
            k += 1
            print(("PASS " if ok else "FAIL ") + msg)
    print(f"\n{'ALL PASS' if allok and k else 'FAILURES'} ({k} files)")
