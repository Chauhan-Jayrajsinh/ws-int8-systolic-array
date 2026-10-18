"""
int_ref.py -- pure-integer reference for the INT8 MLP demo (S1).

Single source of truth for the arithmetic the RTL wrapper must reproduce
bit-for-bit. Forward pass uses Python ints only (no floats, no numpy math).

Dense layer, per output neuron n:
    acc  = bias[n] + sum_k W[n][k] * x[k]          (int32, exact)
    v    = (acc + (1 << (shift-1))) >> shift       (shift > 0; arithmetic
                                                    shift = floor, so ties
                                                    round toward +inf)
         = acc                                     (shift == 0)
    out  = clamp(v, 0 if relu else -128, 127)

Argmax tie-break: lowest index wins (first strict maximum).

Tiled path (dense_acc_tiled) mirrors the planned hardware mapping: 2x2 tiles,
each tile computed by the *project's own* golden_model.py (the model already
proven against the RTL), accumulator preloaded with bias, tiles summed outside
the array.
"""
import json
import os
import sys

INT8_MIN, INT8_MAX = -128, 127
TILE_R, TILE_C = 2, 2                       # matches NUM_ROWS=2, NUM_PE=2
ARRAY_ACC_BITS = 20                         # ACC_WIDTH of the verified array


# ---------------------------------------------------------------- arithmetic
def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


def requant(acc, shift, relu):
    """acc already includes bias. Returns INT8 value as Python int."""
    v = (acc + (1 << (shift - 1))) >> shift if shift > 0 else acc
    return clamp(v, 0 if relu else INT8_MIN, INT8_MAX)


def dense_acc(W, x, b):
    """Exact int accumulators: bias + W @ x. W is list of rows."""
    return [b[n] + sum(w * xi for w, xi in zip(W[n], x)) for n in range(len(W))]


def dense_acc_tiled(W, x, b, stats=None):
    """Same result as dense_acc, computed as 2x2 array tiles (window i=0 only)."""
    import numpy as np
    _import_golden()
    from golden_model import golden_model
    rows, cols = len(W), len(x)
    assert rows % TILE_R == 0 and cols % TILE_C == 0, "dims must be multiples of tile"
    acc = list(b)                                       # accumulator preloaded with bias
    lim = 1 << (ARRAY_ACC_BITS - 1)
    for r0 in range(0, rows, TILE_R):
        for c0 in range(0, cols, TILE_C):
            Wt = np.array([W[r0 + i][c0:c0 + TILE_C] for i in range(TILE_R)], dtype=np.int64)
            Y = golden_model(Wt, x[c0:c0 + TILE_C])      # shape (TILE_R, 1)
            for i in range(TILE_R):
                p = int(Y[i][0])
                assert -lim <= p < lim, "tile partial exceeds array ACC_WIDTH"
                if stats is not None:
                    stats["max_tile_partial"] = max(stats.get("max_tile_partial", 0), abs(p))
                acc[r0 + i] += p
    return acc


def argmax_first(v):
    best = 0
    for i in range(1, len(v)):
        if v[i] > v[best]:
            best = i
    return best


# --------------------------------------------------------------------- model
def load_model(d):
    """Read the exact files the RTL ROMs will later read ($readmemh)."""
    with open(os.path.join(d, "params.json")) as f:
        p = json.load(f)
    n_in, n_hid, n_out = p["n_in"], p["n_hid"], p["n_out"]
    w1 = read_hex(os.path.join(d, "w1.hex"), 8)
    b1 = read_hex(os.path.join(d, "b1.hex"), 32)
    w2 = read_hex(os.path.join(d, "w2.hex"), 8)
    b2 = read_hex(os.path.join(d, "b2.hex"), 32)
    p["W1"] = [w1[r * n_in:(r + 1) * n_in] for r in range(n_hid)]
    p["W2"] = [w2[r * n_hid:(r + 1) * n_hid] for r in range(n_out)]
    p["b1"], p["b2"] = b1, b2
    return p


def forward(m, x_q, tiled=False, stats=None):
    """x_q: list of n_in INT8 ints. Returns (acc1, hidden, acc2, logits, pred)."""
    acc_fn = (lambda W, x, b: dense_acc_tiled(W, x, b, stats)) if tiled else dense_acc
    acc1 = acc_fn(m["W1"], x_q, m["b1"])
    hid = [requant(a, m["shift1"], relu=True) for a in acc1]
    acc2 = acc_fn(m["W2"], hid, m["b2"])
    logits = [requant(a, m["shift2"], relu=False) for a in acc2]
    return acc1, hid, acc2, logits, argmax_first(logits)


# ------------------------------------------------------------------ file I/O
def read_hex(path, bits):
    out = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            v = int(s, 16)
            out.append(v - (1 << bits) if v >= (1 << (bits - 1)) else v)
    return out


def write_hex(path, vals, bits):
    w, mask = bits // 4, (1 << bits) - 1
    with open(path, "w") as f:
        for v in vals:
            f.write(f"{v & mask:0{w}x}\n")


def _import_golden():
    try:
        import golden_model  # noqa: F401
    except ImportError:
        d = os.environ.get("GOLDEN_DIR")
        if not d:
            raise SystemExit("golden_model.py not found: put this folder next to it "
                             "or set GOLDEN_DIR=<dir containing golden_model.py>")
        sys.path.insert(0, d)
