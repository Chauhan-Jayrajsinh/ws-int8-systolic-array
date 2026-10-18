# WS-INT8 Systolic Array — Experiment Log

## Experiment 1: INT8 software reference

- Date: 2026-10-18
- Model: 64 -> 16 -> 10 MLP
- Dataset: scikit-learn digits
- Random seed: 0
- Quantization shifts: shift1=10, shift2=7
- Floating-point test accuracy: 96.11% (540 samples)
- INT8 test accuracy: 96.30% (540 samples)
- Exported-vector accuracy: 246/256 (96.09375%)
- Python reference checks: ALL PASS
- RTL end-to-end equivalence: NOT YET VERIFIED

## Rules

- Record the exact command and tool versions for each experiment.
- Keep software accuracy separate from RTL verification results.
- Record latency separately from accuracy.
- Record synthesis and PPA only when actual reports are available.
- Do not overwrite older results; identify new runs by date or experiment ID.
