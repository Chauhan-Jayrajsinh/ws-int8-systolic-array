"""
test_systolic_array.py -- minimal Cocotb harness for systolic_array.

Purpose of THIS first test: not new verification. Sec 6.1-6.6 (directed,
Verilog TB) already closed correctness for this exact config. This test's
only job is to confirm the Cocotb+golden-model HARNESS ITSELF is trustworthy
by reproducing an already-known-correct result. Once this passes, the same
harness is the foundation for randomized/scaled coverage (the actual reason
this layer exists -- see golden_model.py's TODO).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np

from golden_model import golden_model

NUM_PE = 2
NUM_ROWS = 2
DATA_WIDTH = 8
ACC_WIDTH = 20


async def reset_dut(dut):
    dut.rst_n.value = 0
    await Timer(20, unit="ns")
    dut.rst_n.value = 1
    await Timer(1, unit="ns")


def pack_weights(W: np.ndarray) -> int:
    """
    TODO: pack a (NUM_ROWS, NUM_PE) weight matrix into the integer value
    for dut.weight_in_flat, matching systolic_array.v's row-major
    convention (Sec 2) AND pe_row's PE0=LSB convention within each row --
    the same convention tb_systolic_array.v's load_array_weights already
    got right after the Sec 6.1 debug. Reuse that logic, don't re-derive
    it from scratch.
    """
    packed = 0

    for row in range(NUM_ROWS):
        for col in range(NUM_PE):
            weight = int(W[row][col])
            weight = weight & ((1 << DATA_WIDTH) - 1)
            offset = row * NUM_PE * DATA_WIDTH + col * DATA_WIDTH
            # now put weight at offset
            packed = packed | (weight << offset)
    return packed
# raise NotImplementedError


def extract_row_psum(psum_out_flat: int, row: int) -> int:
    """
    TODO: slice the row-th ACC_WIDTH-wide field out of psum_out_flat and
    convert from two's-complement to a signed Python int (cocotb handles
    values as unsigned by default -- don't repeat the Sec 6.4 signedness
    display mistake here, this time it would affect the actual comparison,
    not just a printout).
    """
    offset = row * ACC_WIDTH
    shifted = psum_out_flat >> offset
    raw = shifted & ((1 << ACC_WIDTH) - 1)
    if raw >= (1 << (ACC_WIDTH - 1)) :
        raw = raw - (1 << ACC_WIDTH)
    return raw
# raise NotImplementedError


@cocotb.test()
async def test_basic_correctness_matches_golden_model(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    W = np.array([[2, 3], [4, 5]])
    EXT = [1, 2, 3, 4, 5]
    expected = golden_model(W, EXT)  # already verified against Sec 6.1 by hand

    dut.load_compute_sel.value = 0
    dut.weight_in_flat.value = pack_weights(W)
    dut.activation_in.value = 0

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    dut.load_compute_sel.value = 1

    # TODO: drive EXT one value per cycle via dut.activation_in.value.
    # After each cycle, check extract_row_psum() against `expected` ONLY
    # once that row's output is valid -- reuse the corrected
    # systolic_array_timing_table.md as your validity reference (row r
    # valid starting local index i=1, relayed r cycles late). Use
    # cocotb's assert, not a manual pass/fail counter -- cocotb reports
    # test results natively.

    n_outputs = len(EXT) - NUM_PE + 1

    for cycle in range(len(EXT)):

        # Drive one activation per cycle
        dut.activation_in.value = EXT[cycle]
        dut.load_compute_sel.value = 1

        # Wait for RTL to process it
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        # Check outputs only when valid
        for row in range(NUM_ROWS):
            output_index = cycle - (NUM_PE - 1) - row

            if 0 <= output_index < n_outputs:
                actual = extract_row_psum(
                    int(dut.psum_out_flat.value), row
                )
                expected_value = expected[row][output_index]

                assert actual == expected_value, (
                    f"Row {row}, output {output_index}: "
                    f"actual={actual}, expected={expected_value}"
                )

@cocotb.test()
async def test_weight_reload_midstream(dut):
    """Reload mid-stream: verify psum preservation and post-reload output."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    W1, EXT1 = np.array([[2, 3], [4, 5]]), [1, 2, 3]
    expected1 = golden_model(W1, EXT1)
    n_out1 = len(EXT1) - NUM_PE + 1

    dut.load_compute_sel.value = 0
    dut.weight_in_flat.value = pack_weights(W1)
    dut.activation_in.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.load_compute_sel.value = 1

    last_psum = None
    for c in range(len(EXT1)):
        dut.activation_in.value = EXT1[c]
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        last_psum = int(dut.psum_out_flat.value)

        for row in range(NUM_ROWS):
            idx = c - (NUM_PE - 1) - row
            if 0 <= idx < n_out1:
                assert extract_row_psum(last_psum, row) == expected1[row][idx]

    assert last_psum != 0

    # Reload weights while preserving partial sums
    W2 = np.array([[7, 6], [4, 5]])
    dut.load_compute_sel.value = 0
    dut.weight_in_flat.value = pack_weights(W2)
    dut.activation_in.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    psum_after = int(dut.psum_out_flat.value)
    assert psum_after == last_psum

    # Resume computation with new weights
    EXT2 = [1, 2, 3]
    expected2 = golden_model(W2, EXT2)
    n_out2 = len(EXT2) - NUM_PE + 1

    dut.load_compute_sel.value = 1
    for c in range(len(EXT2)):
        dut.activation_in.value = EXT2[c]
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        psum = int(dut.psum_out_flat.value)
        if c == 0:
            assert extract_row_psum(psum, 0) == 12
            assert extract_row_psum(psum, 1) == 8
        for row in range(NUM_ROWS):
            idx = c - (NUM_PE - 1) - row

            if 0 <= idx < n_out2:
                assert extract_row_psum(psum, row) == expected2[row][idx]


def step_reload_reference(psums, relays, weights, activation, loading):
    """Model one clock edge for reload coherence, not the MAC golden model."""
    row_inputs = [activation] + relays[:-1]
    next_psums = [row_psums[:] for row_psums in psums]

    if not loading:
        for row in range(NUM_ROWS):
            for col in range(NUM_PE):
                incoming_psum = 0 if col == 0 else psums[row][col - 1]
                next_psums[row][col] = (
                    incoming_psum + row_inputs[row] * int(weights[row][col])
                )

    # Every PE registers activation_out, including during load cycles.
    next_relays = row_inputs[:]
    next_rows = [row_psums[-1] for row_psums in next_psums]
    return next_psums, next_relays, next_rows


async def check_reload_cycle(dut, psums, relays, weights, activation, loading, label):
    expected_psums, expected_relays, expected_rows = step_reload_reference(
        psums, relays, weights, activation, loading
    )

    dut.load_compute_sel.value = 0 if loading else 1
    dut.weight_in_flat.value = pack_weights(weights)
    dut.activation_in.value = activation
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    actual_rows = [
        extract_row_psum(int(dut.psum_out_flat.value), row)
        for row in range(NUM_ROWS)
    ]
    assert actual_rows == expected_rows, (
        f"{label}: activation={activation}, loading={loading}, "
        f"expected rows={expected_rows}, actual rows={actual_rows}"
    )
    return expected_psums, expected_relays


@cocotb.test()
async def test_reload_under_stream_coherence(dut):
    """Check one- and two-cycle weight loads without disturbing stream state."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    w_initial = np.array([[2, 3], [4, 5]])
    w_reload = np.array([[7, 6], [8, 9]])
    scenarios = [
        ("one_cycle_held", [3]),
        ("one_cycle_zero", [0]),
        ("one_cycle_distinct_nonzero", [7]),
        ("two_cycle_held", [3, 3]),
        ("two_cycle_zero", [0, 0]),
        ("two_cycle_distinct_nonzero", [7, 9]),
    ]

    for scenario_name, load_activations in scenarios:
        await reset_dut(dut)
        psums = [[0] * NUM_PE for _ in range(NUM_ROWS)]
        relays = [0] * NUM_ROWS

        psums, relays = await check_reload_cycle(
            dut, psums, relays, w_initial, 0, True,
            f"{scenario_name}/initial_load"
        )
        psums, relays = await check_reload_cycle(
            dut, psums, relays, w_initial, 3, False,
            f"{scenario_name}/preload_compute"
        )

        preserved_psums = [row_psums[:] for row_psums in psums]
        for index, activation in enumerate(load_activations):
            psums, relays = await check_reload_cycle(
                dut, psums, relays, w_reload, activation, True,
                f"{scenario_name}/reload_{index}"
            )
            assert psums == preserved_psums, (
                f"{scenario_name}/reload_{index}: psums changed during load"
            )

        for index, activation in enumerate([1, 2]):
            psums, relays = await check_reload_cycle(
                dut, psums, relays, w_reload, activation, False,
                f"{scenario_name}/post_reload_{index}"
            )

@cocotb.test()
async def test_randomized_against_golden_model(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    await reset_dut(dut)
    rng = np.random.default_rng(42)

    for test_id in range(20):
        activations = rng.integers(-128, 128, size=NUM_PE)
        weights     = rng.integers(-128, 128, size= (NUM_ROWS, NUM_PE))

        # TODO:
        # 1. Load weights
        dut.load_compute_sel.value = 0  # Load Mode
        dut.weight_in_flat.value = pack_weights(weights)
        await RisingEdge(dut.clk)

        # 2. Apply activation sequence
        dut.load_compute_sel.value = 1  # Compute Mode
        for activation in activations:
            dut.activation_in.value = int(activation)
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")

        # 3. Run DUT
        dut.load_compute_sel.value = 1 # Compute Mode

        for activation in activations:
            dut.activation_in.value = int(activation)
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")

            # Outputs are now updated and can be sampled here.
            psum_out = int(dut.psum_out_flat.value)

        # 4. Calculate expected outputs using golden_model.py
        expected_outputs = golden_model(weights, activations)
        n_outputs = len(activations) - NUM_PE + 1

        # 5. Compare cycle-aligned outputs
        for cycle, activation in enumerate(activations):
            dut.activation_in.value = int(activation)
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")

            psum_out = int(dut.psum_out_flat.value)

            for row in range(NUM_ROWS):
                    output_index = cycle - (NUM_PE - 1) - row

                    if 0 <= output_index < n_outputs:
                        actual_output = extract_row_psum(psum_out, row)
                        expected_output = expected_outputs[row][output_index]
                        assert actual_output == expected_output, (
                            f"Test {test_id}, Row {row}, Output {output_index}:"
                            f" actual={actual_output}, expected={expected_output}"
                        )

@cocotb.test()
async def test_signed_int8_edge_cases(dut):
    """Test edge cases for signed 8-bit integers."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    edge_cases = [-128, -1, 0, 1, 127]

    for value in edge_cases:
        await reset_dut(dut)
        # Test the packing and extraction functions
        weights = np.full((NUM_ROWS, NUM_PE), value, dtype=np.int64)
        activations = np.array([1, -1, 2, -2], dtype=np.int64)
        expected_outputs= golden_model(weights, activations)
        n_outputs = len(activations) - NUM_PE + 1

        dut.load_compute_sel.value = 0
        dut.weight_in_flat.value = pack_weights(weights)
        dut.activation_in.value = 0
        await RisingEdge(dut.clk)

        dut.load_compute_sel.value = 1
        for cycle, activation in enumerate(activations):
            dut.activation_in.value = int(activation)
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")

            for row in range(NUM_ROWS):
                output_index = cycle - (NUM_PE - 1) - row
                if 0 <= output_index < n_outputs:
                    psum_out = int(dut.psum_out_flat.value)
                    actual_output = extract_row_psum(psum_out, row)
                    expected_output = expected_outputs[row][output_index]

                    assert actual_output == expected_output, (
                        f"INT8 : Edge case value {value}, Row {row}, Output {output_index}:"
                        f" actual={actual_output}, expected={expected_output}"
                    )