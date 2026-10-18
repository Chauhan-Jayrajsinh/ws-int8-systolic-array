"""
test_int_ref.py -- S1 checks. Run:  GOLDEN_DIR=<dir with golden_model.py> python3 test_int_ref.py
Expected values in T1 were hand-derived BEFORE running (predict-then-verify).
"""
import os
import int_ref as R

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "export")
fails = 0


def check(name, got, exp):
    global fails
    ok = got == exp
    fails += (not ok)
    print(f"{'PASS' if ok else 'FAIL'} {name}" + ("" if ok else f"  got={got} exp={exp}"))


# ---- T1: requant, hand-derived expected values
# (acc, shift, relu) -> expected
T1 = [
    ((4, 3, False), 1),      # (4+4)>>3 = 1            tie rounds up
    ((3, 3, False), 0),      # (3+4)>>3 = 0
    ((-4, 3, False), 0),     # (-4+4)>>3 = 0           negative tie rounds toward +inf
    ((-5, 3, False), -1),    # (-5+4)>>3 = -1>>3 = -1  arithmetic shift = floor
    ((1000, 3, False), 125), # 1004>>3 = 125
    ((1100, 3, False), 127), # 1104>>3 = 138 -> saturate high
    ((-2000, 3, False), -128),  # (-1996)>>3 = -250 -> saturate low
    ((-2000, 3, True), 0),   # ReLU clamps negatives to 0
    ((1, 1, False), 1),      # (1+1)>>1 = 1
    ((-1, 1, False), 0),     # (-1+1)>>1 = 0
    ((-3, 1, False), -1),    # (-3+1)>>1 = -1
    ((5, 0, False), 5),      # shift 0: passthrough
    ((200, 0, False), 127),
    ((-129, 0, False), -128),
    ((127, 0, True), 127),
    ((-1, 0, True), 0),
]
for (a, s, r), e in T1:
    check(f"requant acc={a} shift={s} relu={r}", R.requant(a, s, r), e)

# argmax tie-break
check("argmax first-max tie", R.argmax_first([1, 5, 5, 2]), 1)

# ---- T2: model files round-trip and tiled == untiled, bit-exact, whole exported set
m = R.load_model(D)
n = 256
xs = R.read_hex(f"{D}/test_x.hex", 8)
eh = R.read_hex(f"{D}/expected_hidden.hex", 8)
el = R.read_hex(f"{D}/expected_logits.hex", 8)
labels = [int(l) for l in open(f"{D}/test_labels.txt")]
check("vector file sizes", (len(xs), len(eh), len(el), len(labels)),
      (n * m["n_in"], n * m["n_hid"], n * m["n_out"], n))
check("weight value range [-127,127]",
      all(-127 <= w <= 127 for W in (m["W1"], m["W2"]) for row in W for w in row), True)
check("input range [0,127]", all(0 <= v <= 127 for v in xs), True)

mism, st = 0, {}
max_acc, correct = 0, 0
for i in range(n):
    x = xs[i * m["n_in"]:(i + 1) * m["n_in"]]
    a1, h, a2, lg, p = R.forward(m, x)
    a1t, ht, a2t, lgt, pt = R.forward(m, x, tiled=True, stats=st)
    mism += (a1, h, a2, lg, p) != (a1t, ht, a2t, lgt, pt)
    mism += h != eh[i * m["n_hid"]:(i + 1) * m["n_hid"]]
    mism += lg != el[i * m["n_out"]:(i + 1) * m["n_out"]]
    max_acc = max(max_acc, max(abs(v) for v in a1 + a2))
    correct += (p == labels[i])
check("tiled(golden_model) == untiled == exported, 256 samples", mism, 0)
check("int32 accumulators never overflow", max_acc < 2**31, True)
print(f"INFO max|acc|={max_acc} ({max_acc.bit_length()+1} bits signed), "
      f"max|tile partial|={st['max_tile_partial']} (array ACC_WIDTH=20 limit 524287)")
print(f"INFO exported-set accuracy {correct}/{n}")

print("ALL PASS" if fails == 0 else f"{fails} FAILED")
raise SystemExit(1 if fails else 0)
