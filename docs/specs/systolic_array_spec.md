# systolic_array — Microarchitecture Specification
**Document status:** DRAFT — for implementation
**IP block:** Systolic Array for AI Accelerators — 2D Array Phase
**Module under spec:** `systolic_array`
**Author:** (architect) &nbsp;&nbsp;|&nbsp;&nbsp; **Implementer:** Jayrajsinh Chauhan &nbsp;&nbsp;|&nbsp;&nbsp; **Reviewer:** —

---

## 1. Purpose

`systolic_array` composes `NUM_ROWS` instances of the already-verified `pe_row` block (26/26 PASS at `NUM_PE=3`) into a 2D grid that performs a matrix–vector sliding-window product: each row independently computes its own weighted-sum output stream against a **shared** streamed activation sequence. This is the milestone that turns a single 1×`NUM_PE` reduction into a genuine multi-output-channel accelerator, and is the structure the PPA sweep (your DSE deliverable) will be run across.

This document specifies **what** the block must do and its exact contract. It does not specify internal implementation — that's your design decision, subject to review.

---

## 2. Interface Specification

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Active-low async reset |
| `load_compute_sel` | in | 1 | `0` = load-weight mode, `1` = compute mode (same semantics as `pe_row`/`processing_element`) |
| `activation_in` | in | `DATA_WIDTH` | Activation value, **applies to the whole array this cycle** — see §4.2, work this out yourself, don't assume it's identical to the `pe_row` broadcast decision without re-deriving why |
| `weight_in_flat` | in | `NUM_ROWS * NUM_COLS * DATA_WIDTH` | Flattened bus carrying the full weight matrix (one weight per PE in the grid). Bit-slicing convention is your decision — document it, and make sure it decomposes cleanly into `NUM_ROWS` per-row slices that each match `pe_row`'s own `weight_in_flat` convention |
| `psum_out_flat` | out | `NUM_ROWS * ACC_WIDTH` | One accumulated result per row, flattened. Packing convention is your decision — document it |
| `overflow_flag` | out | 1 | Asserted if **any** row's `overflow_flag` is asserted this cycle |

## 3. Parameters

| Parameter | Default | Constraint |
|---|---|---|
| `DATA_WIDTH` | 8 | Must match the instantiated `pe_row`'s `DATA_WIDTH` |
| `ACC_WIDTH` | 20 | Must match the instantiated `pe_row`'s `ACC_WIDTH` |
| `NUM_COLS` | 3 | Maps to `pe_row`'s `NUM_PE` parameter — ≥ 1 |
| `NUM_ROWS` | 3 | New dimension for this module — ≥ 1. Design must not hardcode a specific value of `NUM_ROWS` (or `NUM_COLS`) anywhere in the logic |

---

## 4. Functional Description

### 4.1 Reuse constraint
`systolic_array` **must be built by instantiating `pe_row` — not by re-deriving row-level MAC/chain logic.** `pe_row` is already verified (26/26, `NUM_PE=3`); re-implementing its behavior here would throw away that verification, same reasoning as §4.1 of `pe_row_spec.md`. If you find yourself writing a psum chain or activation-broadcast wiring directly inside `systolic_array` (rather than inside an instantiated `pe_row`), stop — that logic belongs one level down.

### 4.2 Activation distribution across rows — work this out on paper first
Every row must observe activations from the same shared input sequence. Decide: does every row see the *identical* `activation_in` value on the *same* cycle (a true broadcast across the whole 2D grid, matching how `pe_row` already broadcasts within a row), or is there any reason a systolic array performing a real matrix–vector product would need to skew/stagger activations row-to-row? Think through what mathematical function you get under each choice, the same way §4.2 of `pe_row_spec.md` required you to reason about chaining vs. broadcast within a row, before committing.

### 4.3 Row independence
Unlike columns within a `pe_row` (which chain `psum` between PEs), rows in this design do **not** share or chain partial sums with each other — each row is computing an independent output channel of a matrix–vector product. Confirm this is consistent with your §4.2 answer: if rows are independent outputs, what does that imply about whether `psum_in` for row `r`'s first PE should ever come from another row, versus always being the same identity value each row already uses internally?

### 4.4 Functional intent (black-box behavior)
Treat `systolic_array` as a black box. Given a stationary weight matrix `W[r][c]` for `r = 0..NUM_ROWS-1`, `c = 0..NUM_COLS-1`, and a streamed sequence `x[1], x[2], x[3], ...`, the block should, after warm-up, produce on `psum_out_flat` — for every row `r`, independently:

```
y_r[i] = W[r][0]·x[i] + W[r][1]·x[i+1] + ... + W[r][NUM_COLS-1]·x[i+NUM_COLS-1]
```

a new set of `NUM_ROWS` values (one per row) each cycle once the pipeline is full. **Your job**: determine whether the warm-up latency changes at all from `pe_row`'s `NUM_COLS-1` (hint: since rows don't chain into each other, does adding rows add pipeline depth, or only width?). Write a cycle-by-cycle table before writing RTL, same discipline as `pe_row_timing_table.md`.

### 4.5 Overflow
`overflow_flag` must reflect whether **any** row's `overflow_flag` is currently asserted. Same combining-logic question as `pe_row_spec.md` §4.5, one level up — decide the reduction and be able to justify it for any `NUM_ROWS`, not just 3.

---

## 5. Design Constraints

- Must be parameterizable by both `NUM_ROWS` and `NUM_COLS` independently — a reviewer should be able to set `NUM_ROWS=5, NUM_COLS=3` (or any other combination) and expect correct behavior without editing the module body.
- Must not introduce any new arithmetic beyond what `pe_row` (and transitively, `processing_element`) already provides.
- `weight_in_flat` and `psum_out_flat` bit-slicing/packing conventions are your choice — document them in a header comment, and make sure your testbench's weight-loading and result-checking match exactly. This is the same convention-mismatch risk called out in `pe_row_spec.md` §5, now one level up in hierarchy.
- Known reuse debt from the `pe_row` phase: `tb_pe_row.v`'s `load_row_weights` is hardcoded to positional args for `NUM_PE=3`. Decide whether you need to fix that before or while writing `tb_systolic_array.v`, since a 2D testbench will need to load `NUM_ROWS × NUM_COLS` weights — hardcoding positional args at this scale will not be maintainable across your planned PPA sweep.

---

## 6. Verification Plan (write this before, or alongside, the RTL)

Write directed test cases covering at minimum:

1. **Basic correctness** — load a small weight matrix, stream a short known sequence, verify all `NUM_ROWS` outputs against hand-calculated expected values
2. **Row independence** — confirm that changing one row's weights does not affect any other row's output (this is the property that most directly tests whether §4.3 was implemented correctly)
3. **Weight reload** — same category as `pe_row` §6.2, now across the full matrix; expect the same reload-boundary "stale value held during the load bubble" behavior you already characterized in `pe_row`'s Test 2 — confirm it holds independently per row
4. **Overflow** — decide, using the same reachability analysis as `pe_row`'s Test 3, whether overflow is achievable at your chosen `NUM_ROWS`/`NUM_COLS`/`ACC_WIDTH`; if not, this becomes a documented boundary/non-overflow test, not a gap
5. **Reset behavior** — assert `rst_n` mid-stream, confirm all rows return to a known, documented state
6. **Timing check against your own §4.4 table**

State every expected value **before** running the simulator, same discipline used throughout this project.

---

## 7. Definition of Done

- [ ] `verilator --lint-only -Wall` clean (or every warning explicitly understood and justified)
- [ ] All directed tests in §6 pass, self-checking pass/fail output
- [ ] Waveform reviewed and visually confirms the §4.4 timing table
- [ ] Design decisions from §4.2–§4.5 documented in a comment block at the top of `systolic_array.v`

---

## 8. Design Decisions Log (fill in as you go)

| Decision | Your choice | Rationale |
|---|---|---|
| Activation distribution across rows (§4.2) | | |
| Row independence / psum handling (§4.3) | | |
| `weight_in_flat` bit-slice convention (§5) | | |
| `psum_out_flat` packing convention (§2) | | |
| Overflow combining logic (§4.5) | | |
| `load_row_weights`/array-level weight-loading fix (§5) | | |
