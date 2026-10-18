"""
golden_model.py -- reference model for systolic_array, per
systolic_array_spec.md Sec 4.4 (already proven, not re-derived here).

Y[r][i] = sum_c W[r][c] * EXT[i+c]

Verified against systolic_array_timing_table.md (corrected version) before
being handed off -- Row0: [8,13,18,23], Row1: [14,23,32] reproduced exactly.
This is the SAME formula already proven and DUT-confirmed in Sec 6.1/6.3 --
its job now is breadth (random/scaled coverage via Cocotb), not rediscovery.
"""
import numpy as np


def golden_model(W: np.ndarray, EXT) -> np.ndarray:
    """
    W:   (NUM_ROWS, NUM_PE) int weight matrix, W[r][c]
    EXT: 1D external activation stream
    Returns Y[r][i], 0-indexed, shape (NUM_ROWS, len(EXT)-NUM_PE+1)
    """
    R, C = W.shape
    N = len(EXT)
    n_outputs = N - C + 1
    Y = np.zeros((R, n_outputs), dtype=np.int64)
    for r in range(R):
        for i in range(n_outputs):
            Y[r][i] = sum(W[r][c] * EXT[i + c] for c in range(C))
    return Y


if __name__ == "__main__":
    # TODO (yours): extend with a randomized stimulus generator --
    # random NUM_ROWS/NUM_PE within INT8 signed bounds (-128..127),
    # random EXT sequence, feed into this model, and compare against
    # cocotb-driven DUT output. That's the actual breadth-coverage
    # step this file exists to enable -- not implemented here yet.
    W = np.array([[2, 3], [4, 5]])
    EXT = [1, 2, 3, 4, 5]
    print(golden_model(W, EXT))
