# Systolic Array Timing Table (CORRECTED)
**Status:** Supersedes the original version, which had a 1-cycle warm-up
miscount (valid-window shown one cycle late for both rows). Correction
identified and cross-derived during tb_systolic_array.v Sec 6.1/6.3 debug,
independently confirmed against actual DUT output.

## Configuration
- NUM_ROWS = 2, NUM_PE = 2
- Row 0 weights = [2, 3], Row 1 weights = [4, 5]
- EXT = [1, 2, 3, 4, 5]

## Cycle-by-Cycle Timing (governing rule: PE_i_out(c) = PE_(i-1)_out(c-1) + w_i*x(c); warm-up = NUM_PE-1 = 1 cycle)

| EXT | Row 0 input | Row 0 output | Row 0 valid? | Row 1 input | Row 1 output | Row 1 valid? |
|:---:|:-----------:|:-------------:|:---:|:-----------:|:-------------:|:---:|
| 1 | 1 | 3  | not yet | 0 | 0  | not yet |
| 2 | 2 | 8  | **valid — y[1]** | 1 | 5  | not yet |
| 3 | 3 | 13 | valid — y[2] | 2 | 14 | **valid — y[1]** |
| 4 | 4 | 18 | valid — y[3] | 3 | 23 | valid — y[2] |
| 5 | 5 | 23 | valid — y[4] | 4 | 32 | valid — y[3] |

Row 1's `y[i]` is valid exactly 1 cycle after Row 0's `y[i]` — confirmed both
algebraically (systolic_array_spec.md §4.4) and via DUT-observed timing
(tb_systolic_array.v §6.3, PASS).
