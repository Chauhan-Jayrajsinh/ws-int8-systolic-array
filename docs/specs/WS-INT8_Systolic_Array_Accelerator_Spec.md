# WS-INT8 Systolic Array Accelerator — Technical Specification
**Status:** DRAFT — reflects verified PE, specified (unsimulated) row, pending signedness pass
**Scope:** Single-PE and PE-row level (Week 2–3 milestones). 2D array is future scope.

---

## 1. Fundamentals

The WS-INT8 Systolic Array Accelerator is a weight-stationary, INT8, integer-only MAC pipeline for quantized neural-network **inference** (no training hardware, no scale/zero-point registers on-chip). It is built bottom-up: a single processing element (PE) first, then a row of PEs, then (future) a 2D array. Each level is fully verified before the next is built — the row must not re-derive MAC logic; it must instantiate the already-verified PE.

The accelerator's job is strictly the integer multiply-accumulate on already-quantized values. Quantization scale/zero-point handling lives entirely outside the accelerator, at weight-preparation time and (optionally, as future work) at a downstream requantization stage.

## 2. Architecture

```
                 weight_in            weight_in
                    │                    │
   activation_in ──►[ PE 0 ]──► activation_out (unused for row broadcast)
                    │  psum_in=0
                    ▼
                 psum_out ──► psum_in [ PE 1 ] ──► psum_out ──► psum_in [ PE 2 ] ──► psum_out (row result)
```

- **PE**: one stationary weight register, one multiply, one accumulate, one overflow check.
- **Row (`pe_row`)**: `NUM_PE` instances of `processing_element`, chained on `psum`, broadcast on `activation_in`.
- **Array (future)**: rows tiled to perform full 2D matrix multiply; PPA swept across array sizes as the project's central deliverable.

## 3. Weight-Stationary Dataflow

Each PE holds one weight in `weight_reg` for the duration of a compute phase; it is loaded once (`load_compute_sel = 0`) and reused across every subsequent compute cycle (`load_compute_sel = 1`) until explicitly reloaded. This is the defining dataflow choice baked into the "WS" in the project name — weights don't move once loaded; activations stream through instead. It matches the precedent set by Google TPU v1's weight-stationary INT8 systolic array, which is the reference architecture for this project.

At the row level, every PE observes the **same** `activation_in` on the same cycle (broadcast), not a chain of one PE's registered output feeding the next PE's input. Broadcasting — not chaining — is what produces the intended sliding-window weighted sum across a streamed sequence; chaining activations would compute a different, incorrect function.

## 4. Signed INT8 Arithmetic

"INT8" means signed 8-bit (symmetric range, −128..127) by convention, because real quantized weight and activation distributions are centered near zero. The current RTL is unsigned throughout — ports, registers, the multiply, and the extension logic all lack `signed` declarations, and the testbench validates `8'd255` as +255 rather than its two's-complement value of −1. This is the one substantive gap between the current RTL and what "WS-INT8" requires; everything else in the architecture is already correct (see §9).

## 5. PE/MAC Functionality

Per cycle, in compute mode:

```
mult_result    = activation_in * weight_reg        // signed × signed, 2×DATA_WIDTH bits
sum_result     = sign_extend(psum_in) + sign_extend(mult_result)   // ACC_WIDTH+1 bits, signed add
psum_out      <= sum_result[ACC_WIDTH-1:0]
overflow_flag <= (sum_result[ACC_WIDTH] != sum_result[ACC_WIDTH-1])   // signed overflow, not carry-out
activation_out <= activation_in                     // registered pass-through, for chaining use cases
```

In load mode (`load_compute_sel = 0`): `weight_reg <= weight_in`; no arithmetic occurs. Reset is async active-low, clearing `weight_reg`, `activation_out`, `psum_out`, `overflow_flag` to zero.

## 6. Why ACC_WIDTH = 20

`ACC_WIDTH = 2×DATA_WIDTH + ceil(log2(N))`, with `DATA_WIDTH = 8` and sized for accumulation depth `N = 16` terms: `16 + ceil(log2(16)) = 16 + 4 = 20`.

- `2×DATA_WIDTH = 16` bits covers the full product range of an 8×8 multiply.
- `ceil(log2(N))` extra bits absorb the growth from summing up to `N` such products without overflowing the accumulator itself.

This derivation is **unchanged by signedness**: a signed 8×8 product's range (min `−128×127 = −16256`, max `−128×−128 = 16384`) still fits within 16 bits, since 16384 is within the signed 16-bit range (max 32767). No width increase is required for the signedness pass — only the extension and comparison logic around the existing width changes.

## 7. Overflow Handling

The carry-out bit (`sum_result[ACC_WIDTH]` alone) is a valid overflow test **only for unsigned addition**. Under signed arithmetic it produces both false positives and false negatives. The correct signed-overflow test: sign-extend both addends by one guard bit, perform the add, then compare the top two bits of the result — if they differ, the true signed sum exceeded the representable range and wrapped:

```
overflow_flag <= (sum_result[ACC_WIDTH] != sum_result[ACC_WIDTH-1])
```

This single comparison is both necessary and sufficient for signed-add overflow at any width, which is why it replaces the carry-based check rather than supplementing it.

At the row level, `overflow_flag` is the bitwise OR of every PE's individual `overflow_flag` in that cycle — correct for any `NUM_PE` because OR-reduction over N single-bit flags is exactly "at least one of N conditions is true," independent of N.

## 8. Examples

**Signed MAC, no overflow:** weight = −5, activation = 3, psum_in = 100 → mult_result = −15 → psum_out = 85, overflow_flag = 0.

**Signed MAC, negative overflow (underflow):** with ACC_WIDTH = 20, the signed representable range is −524288..524287. A large negative psum_in combined with a large negative mult_result that sums below −524288 must assert overflow_flag = 1 — this is the case the old unsigned/carry-based test cannot detect at all, since there is no carry-out to observe on a result that is too negative rather than too large.

**Row-level sliding sum (NUM_PE = 3):** weights `w[0], w[1], w[2]` stationary; streamed sequence `x[1], x[2], x[3], ...`. After warm-up, `psum_out` on each cycle equals `w[0]·x[i] + w[1]·x[i+1] + w[2]·x[i+2]` for the current window `i`, advancing by one term each cycle — the exact cycle `y[1]` first appears, and the row's state on every cycle before/after, is worked out as a timing table before RTL is written (per `pe_row_spec.md` §4.4), not left to be inferred from waveforms afterward.

## 9. Required RTL/Testbench Changes

Confined entirely to `processing_element.v` and `tb_processing_element.v`; `pe_row.v` inherits the fix automatically through instantiation once simulated, per the reuse constraint in `pe_row_spec.md` §4.1.

| # | Change | File |
|---|---|---|
| 1 | Declare `activation_in`, `weight_in`, `weight_reg`, `psum_in`, `psum_out` as `signed` | `processing_element.v` |
| 2 | Declare `mult_result` `signed` so the multiply is signed × signed, not just its operands | `processing_element.v` |
| 3 | Change `psum_in` + `mult_result` extension from zero-extension to sign-extension | `processing_element.v` |
| 4 | Replace carry-based `overflow_flag` with the signed-overflow comparison (§7) | `processing_element.v` |
| 5 | Re-derive every testbench expected value under signed interpretation (e.g. `8'd255` = −1, not +255) | `tb_processing_element.v` |
| 6 | Add directed cases: negative×positive, positive×negative, negative×negative, and negative-direction (underflow) overflow | `tb_processing_element.v` |

Unchanged: PE datapath structure, weight-stationary control, `ACC_WIDTH = 20`, reset behavior, row-level broadcast/chaining architecture.

## 10. Verification

- All expected values computed by hand **before** running the simulator — the discipline that caught the original `load_weight` same-edge race condition (fixed with `#1` after `@(posedge clk)`), and the same discipline that must be reapplied for every re-derived signed vector.
- Directed tests remain self-checking (pass/fail printed, not manual waveform inspection).
- Verilator (`--lint-only -Wall`) run clean, or every warning explicitly justified.
- At the row level, verification follows `pe_row_spec.md` §6: basic correctness, weight reload mid-sequence, overflow, reset mid-stream, and a timing check against the §4.4 cycle-by-cycle table — each with expected values stated before simulation.

## 11. Title Justification

**WS-INT8 Systolic Array Accelerator** — each term is a load-bearing, currently-true (or in-progress) fact about the design, not aspirational branding:

- **WS** — weight-stationary is the actual, verified dataflow (§3): weights load once and are reused across compute cycles, confirmed by both RTL (no other write path to `weight_reg`) and testbench.
- **INT8** — the datapath is 8-bit (`DATA_WIDTH = 8`) and, once the §9 signedness pass lands, genuinely signed INT8 rather than unsigned bytes mislabeled as INT8.
- **Systolic Array** — PEs are composed by instantiation and chaining (row today, 2D array as planned future scope), not a monolithic or reused-logic shortcut.
- **Accelerator** — deliberately unscoped on size or exact dataflow variant, so the name survives the PPA sweep across array sizes without needing to change, and doesn't overclaim a multi-dataflow comparison that isn't part of current scope.

The name intentionally omits "training" (this is inference-only, §1) and omits any precision other than INT8 (no multi-precision claim exists in the current design).
