"""
test_latency.py -- measured latency of systolic_array (R rows x C=NUM_PE cols).

Edge convention: edge e = e-th rising clock edge with load_compute_sel=1
(e=1 is the first compute edge). Outputs are sampled 1 ns after each edge.

Hand-derived prediction (registered psum chain, 1 relay register per row):
  row r, output i (0-indexed) first appears at edge  i + C + r
  last output of last row at edge                    N + R - 1
Stimulus uses all-positive weights and strictly increasing positive x, so every
output value is first reached at exactly its predicted edge (partial sums during
warm-up are strictly smaller) -> a first-match search is unambiguous.
"""
import csv
import os

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from golden_model import golden_model

R = int(os.environ.get("LAT_R", "2"))
C = int(os.environ.get("LAT_C", "2"))
N = int(os.environ.get("LAT_N", "8"))
DATA_WIDTH = 8
ACC_WIDTH = 20
CSV_PATH = "latency_results.csv"


def pack_weights(W):
    """Row-major, PE0 = LSB slice within each row (matches systolic_array.v / pe_row.v)."""
    packed = 0
    for r in range(R):
        for c in range(C):
            w = int(W[r][c]) & ((1 << DATA_WIDTH) - 1)
            packed |= w << (r * C * DATA_WIDTH + c * DATA_WIDTH)
    return packed


def extract_row(flat, row):
    raw = (flat >> (row * ACC_WIDTH)) & ((1 << ACC_WIDTH) - 1)
    return raw - (1 << ACC_WIDTH) if raw >= (1 << (ACC_WIDTH - 1)) else raw


@cocotb.test()
async def test_latency_edges(dut):
    n = N - C + 1
    assert n >= 1, f"need N >= C (N={N}, C={C})"
    assert N <= 127, "keep x inside signed INT8"
    t_pred = N + R - 1

    W = np.array([[r * C + c + 2 for c in range(C)] for r in range(R)])  # 2x2 -> [[2,3],[4,5]]
    x = list(range(1, N + 1))
    stream = x + [0] * (R - 1)            # R-1 drain edges so the last row finishes
    expected = golden_model(W, x)         # shape (R, n)

    # Hand-derived table (written before any run) for the 2x2, N=8 case
    if (R, C, N) == (2, 2, 8):
        assert list(expected[0]) == [8, 13, 18, 23, 28, 33, 38]
        assert list(expected[1]) == [14, 23, 32, 41, 50, 59, 68]

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # reset, release on a falling edge (away from the sampling edge)
    dut.rst_n.value = 0
    dut.load_compute_sel.value = 0
    dut.activation_in.value = 0
    dut.weight_in_flat.value = 0
    await ClockCycles(dut.clk, 3)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(1, unit="ns")

    # one-cycle parallel weight load
    dut.load_compute_sel.value = 0
    dut.weight_in_flat.value = pack_weights(W)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # compute edges 1..t_pred
    trace = []                            # trace[e-1] = (per-row psums, overflow bits)
    for e in range(1, t_pred + 1):
        dut.load_compute_sel.value = 1
        dut.activation_in.value = stream[e - 1]
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        flat = int(dut.psum_out_flat.value)
        ovf = int(dut.overflow_flag_flat.value)
        trace.append(([extract_row(flat, r) for r in range(R)], ovf))

    assert all(ovf == 0 for _, ovf in trace), "overflow_flag_flat asserted unexpectedly"

    first_edge, last_edge = [], []
    for r in range(R):
        seq = [trace[e][0][r] for e in range(t_pred)]
        for i in range(n):
            want = int(expected[r][i])
            pred = i + C + r
            hits = [e + 1 for e, v in enumerate(seq) if v == want]
            assert hits, f"row {r} output {i} (={want}) never appeared; seq={seq}"
            assert hits[0] == pred, (
                f"row {r} output {i} (={want}): first seen at edge {hits[0]}, predicted {pred}; seq={seq}")
        first_edge.append(C + r)          # edge of output i=0, verified above
        last_edge.append(n - 1 + C + r)   # edge of output i=n-1, verified above

    t_meas = max(last_edge)
    assert t_meas == t_pred, f"drain edges measured {t_meas}, predicted {t_pred}"

    scalar = R * C * n                    # MODEL: 1 MAC/cycle, not simulated
    ratio = scalar / t_meas
    util = 100.0 * n / t_meas
    dut._log.info(
        f"R={R} C={C} N={N} n={n} | first valid edges={first_edge} | last edges={last_edge} | "
        f"drain={t_meas} (pred {t_pred}) | scalar model={scalar} | ratio={ratio:.2f}x | util={util:.1f}%")

    new = not os.path.exists(CSV_PATH)
    with open(CSV_PATH, "a", newline="") as f:
        wr = csv.writer(f)
        if new:
            wr.writerow(["R", "C", "N", "n", "first_valid_edges", "last_valid_edges",
                         "drain_edges_measured", "drain_edges_predicted",
                         "scalar_cycles_model", "ratio_vs_scalar_model", "utilization_pct"])
        wr.writerow([R, C, N, n, "|".join(map(str, first_edge)), "|".join(map(str, last_edge)),
                     t_meas, t_pred, scalar, f"{ratio:.2f}", f"{util:.1f}"])
