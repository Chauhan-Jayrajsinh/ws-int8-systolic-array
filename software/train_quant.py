"""
train_quant.py -- train a tiny float MLP (sklearn digits, 64->16->10), apply
post-training symmetric INT8 quantization with power-of-two requant shifts,
and export the frozen artifacts the RTL/cocotb flow will read.

Run once; COMMIT the export/ directory. Downstream steps use the exported
files, never this script, so retraining nondeterminism can't move the goalposts.
"""
import json
import os
import numpy as np
from sklearn.datasets import load_digits
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier

import int_ref as R

SEED = 0
N_IN, N_HID, N_OUT = 64, 16, 10
N_EXPORT = 256                       # test vectors exported for RTL/cocotb (S4 needs >=200)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "export")


def sym_quant(w):
    s = float(np.max(np.abs(w))) / 127.0
    return np.clip(np.rint(w / s), -127, 127).astype(np.int64), s


def smallest_shift(accs, relu):
    """Smallest shift such that no calibration value saturates."""
    lo = 0 if relu else R.INT8_MIN
    for s in range(0, 32):
        if all(lo <= (((a + (1 << (s - 1))) >> s) if s else a) <= R.INT8_MAX
               for a in accs if (not relu) or a > 0):
            return s
    raise RuntimeError("no shift found")


def main():
    os.makedirs(OUT, exist_ok=True)
    X, y = load_digits(return_X_y=True)                 # pixels 0..16
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.3, random_state=SEED, stratify=y)

    clf = MLPClassifier(hidden_layer_sizes=(N_HID,), activation="relu",
                        max_iter=2000, random_state=SEED).fit(Xtr, ytr)
    float_acc = clf.score(Xte, yte)

    # ---- input quantization: 0..16 -> 0..127
    s_in = 16.0 / 127.0
    q_in = lambda A: np.clip(np.rint(A / s_in), 0, 127).astype(np.int64)

    # ---- weights (rows = output neurons) and int32 biases in accumulator scale
    W1f, W2f = clf.coefs_[0].T, clf.coefs_[1].T
    W1q, s_w1 = sym_quant(W1f)
    W2q, s_w2 = sym_quant(W2f)
    b1q = np.rint(clf.intercepts_[0] / (s_in * s_w1)).astype(np.int64)

    # ---- layer-1 shift from calibration on TRAIN set only
    W1l, b1l = W1q.tolist(), b1q.tolist()
    xtr_q = q_in(Xtr).tolist()
    acc1_tr = [a for x in xtr_q for a in R.dense_acc(W1l, x, b1l)]
    shift1 = smallest_shift(acc1_tr, relu=True)
    s_h = s_in * s_w1 * (2 ** shift1)                    # real value of one hidden LSB

    b2q = np.rint(clf.intercepts_[1] / (s_h * s_w2)).astype(np.int64)
    W2l, b2l = W2q.tolist(), b2q.tolist()
    acc2_tr = []
    for x in xtr_q:
        h = [R.requant(a, shift1, True) for a in R.dense_acc(W1l, x, b1l)]
        acc2_tr += R.dense_acc(W2l, h, b2l)
    shift2 = smallest_shift(acc2_tr, relu=False)

    # ---- export model
    R.write_hex(f"{OUT}/w1.hex", W1q.flatten().tolist(), 8)     # row-major [neuron][input]
    R.write_hex(f"{OUT}/b1.hex", b1l, 32)
    R.write_hex(f"{OUT}/w2.hex", W2q.flatten().tolist(), 8)
    R.write_hex(f"{OUT}/b2.hex", b2l, 32)
    params = dict(n_in=N_IN, n_hid=N_HID, n_out=N_OUT, shift1=shift1, shift2=shift2,
                  s_in=s_in, s_w1=s_w1, s_w2=s_w2, s_h=s_h, seed=SEED,
                  float_acc_test=float_acc)
    with open(f"{OUT}/params.json", "w") as f:
        json.dump(params, f, indent=2)

    # ---- export test vectors + expected outputs, produced via the reloaded files
    m = R.load_model(OUT)
    xte_q = q_in(Xte).tolist()
    ex, eh, el, lab = [], [], [], []
    for i in range(N_EXPORT):
        _, h, _, lg, _ = R.forward(m, xte_q[i])
        ex += xte_q[i]; eh += h; el += lg; lab.append(int(yte[i]))
    R.write_hex(f"{OUT}/test_x.hex", ex, 8)
    R.write_hex(f"{OUT}/expected_hidden.hex", eh, 8)
    R.write_hex(f"{OUT}/expected_logits.hex", el, 8)
    with open(f"{OUT}/test_labels.txt", "w") as f:
        f.write("\n".join(map(str, lab)) + "\n")

    # ---- summary
    int_acc = np.mean([R.forward(m, x)[4] == t for x, t in zip(xte_q, yte)])
    print(f"float test acc : {float_acc:.4f}   (n={len(yte)})")
    print(f"INT8  test acc : {int_acc:.4f}   shift1={shift1} shift2={shift2}")
    print(f"exported {N_EXPORT} vectors to {OUT}")


if __name__ == "__main__":
    main()
