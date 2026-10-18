# WS-INT8 Systolic Array — Progress Update

## Purpose

This file records completed work, verification evidence, and next steps. Read it before continuing development. Do not repeat completed work unnecessarily or claim results that have not been verified.

## 1. RTL Architecture and Verification

RTL modules:
- `rtl/processing_element.v`
- `rtl/pe_row.v`
- `rtl/systolic_array.v`

Previously recorded directed verification results:

| Component | Passed | Failed |
|---|---:|---:|
| Processing element | 49 | 0 |
| PE row | 28 | 0 |
| Systolic array | 22 | 0 |

These are previously recorded results, not a claim that the tests were rerun today.

The existing architecture includes a weight-stationary INT8 processing element, PE-row composition, and a 2D systolic array using a hybrid relay architecture.

## 2. Cocotb and Latency Characterization

Existing verification files include:
- `verif/cocotb/golden_model.py`
- `verif/cocotb/test_latency.py`
- `verif/cocotb/test_systolic_array.py`
- `verif/cocotb/Makefile`

A previously recorded initial Cocotb array regression passed 5 tests. Latency characterization was also developed for selected configurations.

Before publishing latency numbers, inspect the actual logs and recorded result files. Do not confuse cycle latency with physical timing or claim synthesis-based PPA without reports.

## 3. INT8 Software Reference and Model Export

Relevant files:
- `software/train_quant.py`
- `software/int_ref.py`
- `software/test_int_ref.py`
- `software/export/params.json`
- `software/export/w1.hex`
- `software/export/b1.hex`
- `software/export/w2.hex`
- `software/export/b2.hex`
- `software/export/test_x.hex`
- `software/export/test_labels.txt`
- `software/export/expected_hidden.hex`
- `software/export/expected_logits.hex`

Previously recorded training results for the 64 → 16 → 10 MLP on the scikit-learn digits dataset:
- Floating-point test accuracy: 96.11% over 540 samples.
- INT8 test accuracy: 96.30% over 540 samples.
- Quantization shifts: `shift1=10`, `shift2=7`.
- Exported test-vector accuracy: 246/256 = 96.09375%.

The Python reference checks previously completed with `ALL PASS`, including tiled/untiled reference consistency and exported-output checks.

**These are software-reference results. They do not establish end-to-end RTL inference or RTL/software equivalence.**

## 4. Git History and Working Tree

Previously recorded commits:
- `1408936` — `Add Cocotb regression and latency characterization`
- `4ac9a95` — `Add INT8 software reference and model exports`

The results-tracking files were created locally in an earlier step, but their current Git status must be checked. Do not assume they have been committed or pushed.

## 5. Results Tracking

Potential result records:
- `results/accuracy.csv`
- `results/verification.csv`
- `results/experiment_log.md`

Inspect the current files and working tree before modifying them. Preserve existing evidence and distinguish previously recorded results from newly rerun tests.

## 6. Not Yet Established

Do not claim any of the following without new, reproducible evidence:
- End-to-end MLP inference through RTL.
- RTL equivalence for all 256 exported test vectors.
- Full MLP hardware integration.
- Synthesis-based area, frequency, power, or PPA.
- Physical timing closure.

## 7. Recommended Next Steps

1. Check `git status` and verify this document.
2. Inspect the actual RTL ports, array timing, Cocotb tests, and latency logs.
3. Establish a small deterministic RTL-versus-Python golden-model comparison.
4. Expand verification only after the interface, signed arithmetic, weight packing, accumulation order, requantization, and cycle timing are understood.
5. Update the B.Tech report using actual logs and clearly stated verification scope.
6. Commit and push only after reviewing the diff and running relevant checks.

## Development Rules

- Inspect interfaces before changing RTL or testbenches.
- Preserve the existing implementation unless a change is justified and requested.
- Avoid unrelated modifications to the root Makefile and existing testbenches.
- Reuse the existing Python golden model where appropriate.
- Record exact commands, tool versions, configurations, and test outcomes.
- Never claim a test passed unless it was actually run and its result was checked.
