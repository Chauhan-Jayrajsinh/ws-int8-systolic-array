# Systolic Array Verification Log

## Cocotb Golden-Model Regression and Latency Characterization

**Date:** 18 October 2026\
**Repository:** `~/systolic-array`\
**Verification directory:** `~/systolic-array/verif/cocotb`

## 1. Purpose

Record the Cocotb/Python golden-model regression and the separate
cycle-accurate latency experiment. This log distinguishes executed tests
from analytical comparisons and does not claim synthesis, PPA, or
physical-hardware measurements.

## 2. Environment and files

-   Simulator: Verilator 5.050
-   Cocotb: 2.1.0
-   Python: 3.10.19
-   RTL: `rtl/processing_element.v`, `rtl/pe_row.v`,
    `rtl/systolic_array.v`
-   Existing regression: `verif/cocotb/Makefile`,
    `test_systolic_array.py`, `golden_model.py`
-   Latency experiment: `verif/cocotb/Makefile.latency`,
    `test_latency.py`, `latency_results.csv`

## 3. Existing Cocotb regression

Run:

``` bash
cd ~/systolic-array/verif/cocotb
make
```

Final observed result:

``` text
TESTS=5 PASS=5 FAIL=0 SKIP=0
```

All five tests passed:

1.  `test_basic_correctness_matches_golden_model`
2.  `test_weight_reload_midstream`
3.  `test_reload_under_stream_coherence`
4.  `test_randomized_against_golden_model`
5.  `test_signed_int8_edge_cases`

An earlier run failed with
`ModuleNotFoundError: No module named 'numpy'`. The
dependency/environment issue was subsequently resolved, but the exact
install command is not present in the available record and is not
reconstructed here.

## 4. Separate latency experiment

Run configuration A:

``` bash
cd ~/systolic-array/verif/cocotb
make -f Makefile.latency NUM_ROWS=2 NUM_PE=2 STREAM_N=8
```

The first attempt compiled RTL but failed with
`ModuleNotFoundError: No module named 'test_latency'`. Inspection showed
that `Makefile.latency` existed but `test_latency.py` had not yet been
created. The test file was then created in the same directory and the
test passed.

The 2×2 run reported:

``` text
R=2 C=2 N=8 n=7 | first valid edges=[2, 3] |
last edges=[8, 9] | drain=9 (pred 9) |
scalar model=28 | ratio=3.11x | util=77.8%
```

Test status: `TESTS=1 PASS=1 FAIL=0 SKIP=0`.

### Final latency results

  -------------------------------------------------------------------------------------------------------------------
  Rows R Columns C Stream N   Outputs First   Last      Measured   Predicted        Scalar  Cycle ratio    Calculated
                            per row n valid   valid        drain       drain   cycle-count   vs. scalar   utilization
                                      edges   edges       cycles      cycles         model        model        metric
                                      by row  by row
  ------ --------- -------- --------- ------- ------- ---------- ----------- ------------- ------------ -------------
       2         2        8         7 2, 3    8, 9             9           9            28        3.11×         77.8%

       3         2        8         7 2, 3, 4 8, 9,           10          10            42        4.20×         70.0%
                                              10

       2         3        8         6 3, 4    8, 9             9           9            36        4.00×         66.7%

       3         3        8         6 3, 4, 5 8, 9,           10          10            54        5.40×         60.0%
                                              10
  -------------------------------------------------------------------------------------------------------------------

The CSV initially contained duplicate rows because the test appends
results on each run. The duplicates were removed, leaving one row per
unique `(R, C, N)` configuration.

For these tested cases, measured drain cycles match the prediction used
by the test:

\[ T\_{`\text{drain}`{=tex}} = N + R - 1 \]

Here `N=8`; `R` is the number of rows. These results do not establish
behavior for other stream lengths.

### Interpretation and limitations

-   This is directed, cycle-accurate RTL latency characterization using
    simulation.
-   Scalar cycle counts are an **analytical model**, not measurements
    from a separately implemented scalar hardware design.
-   The cycle ratio is a comparison against that model, not a measured
    silicon speedup.
-   The utilization percentage is a calculated test metric, not physical
    area or synthesis utilization.
-   The experiment does not establish synthesis results, timing closure,
    area, power, PPA, or silicon performance.

## 5. Commands used during the session

### Inspect files and locate RTL

``` bash
cd ~/systolic-array/verif/cocotb
ls -l
ls -l Makefile.latency test_latency.py
```

``` bash
cd ~/systolic-array
find . -name "systolic_array.v" -o -name "pe_row.v" -o -name "processing_element.v"
grep -nE 'module systolic_array|parameter|input|output' rtl/systolic_array.v
```

Observed RTL paths:

``` text
./rtl/systolic_array.v
./rtl/pe_row.v
./rtl/processing_element.v
```

### Run original regression and latency tests

``` bash
cd ~/systolic-array/verif/cocotb
make

make -f Makefile.latency NUM_ROWS=2 NUM_PE=2 STREAM_N=8

for cfg in "3 2" "2 3" "3 3"; do
  set -- $cfg
  make -f Makefile.latency NUM_ROWS=$1 NUM_PE=$2 STREAM_N=8 || break
done
```

### Display or inspect CSV results

``` bash
column -s, -t latency_results.csv
cat latency_results.csv
```

`column` only formats the terminal display; it does not change the CSV.

To intentionally start a fresh results file (this deletes the current
CSV):

``` bash
rm -f latency_results.csv
```

### Inspect repository changes and checksums

``` bash
cd ~/systolic-array
git status --short
git diff -- Makefile tb/tb_pe_row.v
md5sum -c /tmp/before.md5
```

The checksum command returned `OK` for the seven files in the snapshot:
root `Makefile`, the three RTL files, and three existing Verilog
testbenches. This check only covers files included in `/tmp/before.md5`.

The recorded Git status also showed changes/untracked items outside the
latency files: modified root `Makefile`, modified `tb/tb_pe_row.v`, and
untracked `.github/`, `.venv/`, a waveform image, `software/`, and
`verif/`. Review these before staging or committing; do not assume they
all belong to the latency experiment.

## 6. Suggested report-ready summary

> A Cocotb-based cycle-accurate latency characterization was performed
> on the parameterized systolic-array RTL for four configurations: 2×2,
> 3×2, 2×3, and 3×3, using an eight-element activation stream. The
> observed first-valid and last-valid output edges matched the expected
> timing, and the measured drain counts of 9, 10, 9, and 10 cycles
> matched the predicted values. A scalar cycle-count model was used as
> an analytical comparison baseline. These results are limited to the
> four simulated configurations at N=8.

Use this in the report's verification/results section only after
retaining the test source, CSV, and simulator output. Do not place it in
a section claiming synthesis or PPA.

## 7. Reproducibility checklist

-   [ ] Keep `Makefile.latency`, `test_latency.py`, and
    `latency_results.csv`.
-   [ ] Keep the original `Makefile`, `test_systolic_array.py`, and
    `golden_model.py`.
-   [ ] Retain the final original-regression output (`5 PASS, 0 FAIL`).
-   [ ] Retain outputs or XML results for all four latency runs.
-   [ ] Confirm the CSV has one row per configuration.
-   [ ] Review `git status --short` and inspect unrelated changes before
    staging.
-   [ ] Do not claim synthesis/PPA or physical utilization from these
    simulation results.
