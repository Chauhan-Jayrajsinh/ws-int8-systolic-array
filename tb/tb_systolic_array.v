    `timescale 1ns/1ps
    // ============================================================================
    // tb_systolic_array.v -- Directed testbench for systolic_array
    // Verification Plan (systolic_array_spec.md Sec 6)
    // This file implements Sec 6.1 through Sec 6.6:
    //   6.1 Basic Correctness
    //   6.2 Row Independence
    //   6.3 Row-to-Row Skew Timing
    //   6.4 Overflow, Per Row
    //   6.5 Reset Mid-Stream / Post-Reset Recovery
    //   6.6 NUM_ROWS Scalability Sanity
    //
    // Config under test (matches systolic_array_timing_table.md, verified):
    //   NUM_ROWS = 2, NUM_PE = 2
    //   Row 0 weights = [2, 3]
    //   Row 1 weights = [4, 5]
    //   EXT = [1, 2, 3, 4]
    //
    // RULE (same discipline as tb_processing_element.v / tb_pe_row.v): every
    // expected value below comes from systolic_array_timing_table.md, already
    // hand-derived and cross-checked BEFORE this testbench is written. Do not
    // compute an expected value after seeing simulator output.
    // ============================================================================

    module tb_systolic_array;

        parameter DATA_WIDTH = 8;
        parameter ACC_WIDTH  = 20;
        parameter NUM_PE     = 2;
        parameter NUM_ROWS   = 2;

        reg                                             clk;
        reg                                             rst_n;
        reg                                             load_compute_sel;
        reg  signed [DATA_WIDTH-1:0]                    activation_in;
        reg  signed [NUM_ROWS*NUM_PE*DATA_WIDTH-1:0]    weight_in_flat;
        reg  signed [3*NUM_PE*DATA_WIDTH-1:0]            weight_in_flat_scale;
        wire signed [NUM_ROWS*ACC_WIDTH-1:0]            psum_out_flat;
        wire [NUM_ROWS-1:0]                             overflow_flag_flat;

        // GTKWave observation signals — no DUT logic modification
        /* verilator lint_off UNUSEDSIGNAL */
        wire signed [ACC_WIDTH-1:0] row0_psum_view;
        wire signed [ACC_WIDTH-1:0] row1_psum_view;
        /* verilator lint_on UNUSEDSIGNAL */

        assign row0_psum_view = psum_out_flat[ACC_WIDTH-1:0];
        assign row1_psum_view = psum_out_flat[2*ACC_WIDTH-1:ACC_WIDTH];

        integer tests  = 0;
        integer passed = 0;
        integer failed = 0;

        systolic_array #(
            .DATA_WIDTH(DATA_WIDTH),
            .ACC_WIDTH(ACC_WIDTH),
            .NUM_PE(NUM_PE),
            .NUM_ROWS(NUM_ROWS)
        ) dut (
            .clk(clk),
            .rst_n(rst_n),
            .load_compute_sel(load_compute_sel),
            .activation_in(activation_in),
            .weight_in_flat(weight_in_flat),
            .psum_out_flat(psum_out_flat),
            .overflow_flag_flat(overflow_flag_flat)
        );

        systolic_array #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .NUM_PE(2),
                .NUM_ROWS(3)
            ) dut_scale (
                .clk(clk),
                .rst_n(rst_n),
                .load_compute_sel(load_compute_sel),
                .activation_in(activation_in),
                .weight_in_flat(weight_in_flat_scale),
                .psum_out_flat(psum_out_flat_scale),
                .overflow_flag_flat(overflow_flag_flat_scale)
            );
        wire signed [3*ACC_WIDTH-1:0] psum_out_flat_scale;
        wire [2:0]                    overflow_flag_flat_scale;

        always #5 clk = ~clk;
        // ============================================================================
        // §6.3 ROW-TO-ROW SKEW TIMING CHECK
        // Purpose: Verify Row 1 produces the corresponding output exactly
        //          one clock cycle after Row 0.
        // Method: Passively observe actual DUT outputs.
        // No new stimulus; §6.1 stimulus is reused.
        // ============================================================================

        time row0_valid_time;
        time row1_valid_time;

        always @(posedge clk) begin
            #1;

            if (row0_valid_time == -1 &&
                psum_out_flat[ACC_WIDTH-1:0] === ACC_WIDTH'(8))
                row0_valid_time <= $time;

            if (row1_valid_time == -1 &&
                psum_out_flat[2*ACC_WIDTH-1:ACC_WIDTH] === ACC_WIDTH'(14))
                row1_valid_time <= $time;
        end

        initial begin
            row0_valid_time = -1;
            row1_valid_time = -1;
            $dumpfile("dump_systolic_array.vcd");
            $dumpvars(0, tb_systolic_array);
        end

        task report_case(input string name, input integer local_failures);
        begin
            tests = tests + 1;

            if (local_failures == 0)
                passed = passed + 1;
            else
                failed = failed + 1;

            $display("%s: %s", name, (local_failures == 0) ? "PASS" : "FAIL");
        end
        endtask

        task load_array_weights(
            input signed [NUM_ROWS*NUM_PE*DATA_WIDTH-1:0] weights
        );
        begin
            load_compute_sel = 0;
            weight_in_flat = weights;
            @(posedge clk);
            #1;
        end
        endtask


        task do_compute(
        input signed [DATA_WIDTH-1:0] activation,
        input signed [NUM_ROWS*ACC_WIDTH-1:0] expected_psum
        );
        integer local_failures;
        reg signed [ACC_WIDTH-1:0] r0_out;
        reg signed [ACC_WIDTH-1:0] r1_out;
        begin
            activation_in    = activation;
            load_compute_sel = 1;

            @(posedge clk);
            #1;

            local_failures = 0;

            if (psum_out_flat !== expected_psum)
                local_failures = local_failures + 1;

            if (overflow_flag_flat !== {NUM_ROWS{1'b0}})
                local_failures = local_failures + 1;

            // Force sign extension and width clamping
            r0_out = psum_out_flat[ACC_WIDTH-1:0];
            r1_out = psum_out_flat[2*ACC_WIDTH-1:ACC_WIDTH];

            $display(" %4d | %11d | %11d |    %02b    | %s",
                $signed(activation),
                $signed(r0_out),
                $signed(r1_out),
                overflow_flag_flat,
                (local_failures == 0) ? "PASS" : "FAIL");

            report_case("do_compute", local_failures);
        end
        endtask

        task load_scale_weights(
            input signed [3*NUM_PE*DATA_WIDTH-1:0] weights
        );
        begin
            load_compute_sel = 0;
            weight_in_flat_scale = weights;
            @(posedge clk);
            #1;
        end
        endtask

        task do_scale_compute(
        input signed [DATA_WIDTH-1:0] activation,
        input signed [3*ACC_WIDTH-1:0] expected_psum
        );
        integer local_failures;
        begin
            activation_in    = activation;
            load_compute_sel = 1;

            @(posedge clk);
            #1;

            local_failures = 0;
            if (psum_out_flat_scale !== expected_psum)
                local_failures = local_failures + 1;
            if (overflow_flag_flat_scale !== 3'b000)
                local_failures = local_failures + 1;

            report_case("do_scale_compute", local_failures);
        end
        endtask


        // Target values from systolic_array_timing_table.md (verified):
        //   EXT=1: Row0=3,  Row1=0
        //   EXT=2: Row0=8,  Row1=5
        //   EXT=3: Row0=13, Row1=14
        //   EXT=4: Row0=18, Row1=23
        //   EXT=5: Row0=23, Row1=32
        //
        // overflow_flag_flat is expected to remain 0 for both rows throughout.
        // These values are far below the ACC_WIDTH=20 overflow threshold.

        initial begin
            integer local_failures;

            clk               = 0;
            rst_n             = 0;
            load_compute_sel  = 0;
            activation_in     = 0;
            weight_in_flat    = 0;
            weight_in_flat_scale = 0;

            repeat (2) @(posedge clk);
            rst_n = 1;

            // Load weights: Row 1 = [4,5], Row 0 = [2,3]
            load_array_weights({8'sd5, 8'sd4, 8'sd3, 8'sd2});

            $display("==================================================================");
            $display("§6.1 BASIC CORRECTNESS");
            $display("Config: NUM_ROWS=%0d, NUM_PE=%0d", NUM_ROWS, NUM_PE);
            $display("Weights: Row0=[2,3], Row1=[4,5]");
            $display("==================================================================");
            $display(" EXT | Row0 Output | Row1 Output | Overflow | Result");
            $display("-----+-------------+-------------+----------+-------");

            // Compute mode
            load_compute_sel = 1;

            do_compute(DATA_WIDTH'(1), {ACC_WIDTH'(0),  ACC_WIDTH'(3)});  // EXT=1: Row1=0,  Row0=3
            do_compute(DATA_WIDTH'(2), {ACC_WIDTH'(5),  ACC_WIDTH'(8)});  // EXT=2: Row1=5,  Row0=8
            do_compute(DATA_WIDTH'(3), {ACC_WIDTH'(14), ACC_WIDTH'(13)}); // EXT=3: Row1=14, Row0=13
            do_compute(DATA_WIDTH'(4), {ACC_WIDTH'(23), ACC_WIDTH'(18)}); // EXT=4: Row1=23, Row0=18
            do_compute(DATA_WIDTH'(5), {ACC_WIDTH'(32), ACC_WIDTH'(23)}); // EXT=5: Row1=32, Row0=23

            // ================================================================
            // §6.2 ROW INDEPENDENCE
            // Reload Row 0 weights while preserving Row 1 weights and the
            // existing in-flight partial sums.
            // ================================================================

            $display("");
            $display("==================================================================");
            $display("§6.2 ROW INDEPENDENCE");
            $display("==================================================================");

            // Start from a clean state
            rst_n = 0;
            activation_in = 0;
            #1;
            rst_n = 1;
            #1;
            // Load initial weights:
            // Row 0 = [2,3], Row 1 = [4,5]
            load_array_weights({8'sd5, 8'sd4, 8'sd3, 8'sd2});

            load_compute_sel = 1;

            // Build known non-zero partial sums
            do_compute(DATA_WIDTH'(1), {ACC_WIDTH'(0), ACC_WIDTH'(3)});
            do_compute(DATA_WIDTH'(2), {ACC_WIDTH'(5), ACC_WIDTH'(8)});

            // Reload Row 0 only:
            // Row 0 = [7,6], Row 1 must remain [4,5]
            activation_in = 0;

            load_array_weights({8'sd5, 8'sd4, 8'sd6, 8'sd7});

            // Check weight isolation and psum preservation
            local_failures = 0;

            if (dut.row_inst[1].row.pe_inst[0].pe.weight_reg !== 4)
                local_failures = local_failures + 1;
            if (dut.row_inst[1].row.pe_inst[1].pe.weight_reg !== 5)
                local_failures = local_failures + 1;
            if (dut.row_inst[0].row.pe_inst[0].pe.weight_reg !== 7)
                local_failures = local_failures + 1;
            if (dut.row_inst[0].row.pe_inst[1].pe.weight_reg !== 6)
                local_failures = local_failures + 1;
            if (psum_out_flat !== {ACC_WIDTH'(5), ACC_WIDTH'(8)})
                local_failures = local_failures + 1;

            report_case("ROW_INDEPENDENCE", local_failures);

            $display("Row0 weights=[7,6] | Row1 weights=[4,5] | Psum=[Row1=5, Row0=8]");
            $display("Result=%s", (local_failures == 0) ? "PASS" : "FAIL");

            // ============================================================================
            // §6.3 ROW-TO-ROW SKEW TIMING CHECK
            // Expected: Row 1 corresponding output occurs exactly 1 clock cycle
            //           after Row 0.
            // CLK period = 10 ns.
            // ============================================================================
            $display("");
            $display("==================================================================");
            $display("§6.3 ROW-TO-ROW SKEW TIMING CHECK");
            $display("==================================================================");

            local_failures = 0;
            if (row0_valid_time == -1)
                local_failures = local_failures + 1;
            if (row1_valid_time == -1)
                local_failures = local_failures + 1;
            if ((row1_valid_time - row0_valid_time) !== 10)
                local_failures = local_failures + 1;

            $display("Row0 output=8 | Row1 output=14 | Skew=1 cycle | Expected=1 cycle");

            if (local_failures == 0)
                $display("Result=PASS");
            else
                $display("Result=FAIL");

            report_case("ROW_SKEW_DELTA_EQUALS_ONE_CYCLE", local_failures);

            // ============================================================================
            // §6.4 OVERFLOW, PER ROW
            // Scope: NUM_PE=2, ACC_WIDTH=20 -> genuine overflow is unreachable.
            // This test confirms per-row overflow flags remain 0 under the maximum
            // relevant magnitude stimulus.
            // Expected:
            //   Cycle 1: Row0=16384,  Row1=0
            //   Cycle 2: Row0=32768,  Row1=-16256
            //   Cycle 3: Row0=32768,  Row1=-32512
            //   overflow_flag_flat = 00 throughout.
            // ============================================================================

            $display("");
            $display("==================================================================");
            $display("§6.4 OVERFLOW, PER ROW");
            $display("==================================================================");

            rst_n = 0;
            activation_in = 0;
            #1;
            rst_n = 1;
            #1;

            load_array_weights({8'sd127, 8'sd127, -8'sd128, -8'sd128});
            // Row0=[-128,-128], Row1=[127,127]

            load_compute_sel = 1;

            do_compute(-8'sd128,
                    {ACC_WIDTH'(0), ACC_WIDTH'(16384)});
            // EXT=-128: Row1=0, Row0=16384

            do_compute(-8'sd128,
                    {-ACC_WIDTH'(16256), ACC_WIDTH'(32768)});
            // EXT=-128: Row1=-16256, Row0=32768

            do_compute(-8'sd128,
                    {-ACC_WIDTH'(32512), ACC_WIDTH'(32768)});
            // EXT=-128: Row1=-32512, Row0=32768

            $display("Expected overflow flags: Row0=0 | Row1=0");

            // =============================================================================
            // SECTION 6, ITEM 5 -- RESET BEHAVIOR (systolic_array_spec.md)
            // Objective: reset mid-stream from real non-zero state; confirm
            // (a) immediate known-state, (b) relay register actually clears,
            // proven via full post-reset recovery, not just the immediate check.
            // ==============================================================================

            $display("");
            $display("==================================================================");
            $display("§6.5 RESET MID-STREAM / POST-RESET RECOVERY");
            $display("==================================================================");

            rst_n = 0;
            activation_in = 0;
            #1;
            local_failures = 0;
            if (psum_out_flat !== {NUM_ROWS*ACC_WIDTH{1'b0}})
                local_failures = local_failures + 1;
            if (overflow_flag_flat !== {NUM_ROWS{1'b0}})
                local_failures = local_failures + 1;
            report_case("RESET_MIDSTREAM_STATE", local_failures);
            rst_n = 1;


            load_array_weights({8'sd5, 8'sd4, 8'sd3, 8'sd2});

            load_compute_sel = 1;

            do_compute(DATA_WIDTH'(1), {ACC_WIDTH'(0),  ACC_WIDTH'(3)});  // EXT=1: Row1=0,  Row0=3
            do_compute(DATA_WIDTH'(2), {ACC_WIDTH'(5),  ACC_WIDTH'(8)});  // EXT=2: Row1=5,  Row0=8
            do_compute(DATA_WIDTH'(3), {ACC_WIDTH'(14), ACC_WIDTH'(13)}); // EXT=3: Row1=14, Row0=13
            do_compute(DATA_WIDTH'(4), {ACC_WIDTH'(23), ACC_WIDTH'(18)}); // EXT=4: Row1=23, Row0=18
            do_compute(DATA_WIDTH'(5), {ACC_WIDTH'(32), ACC_WIDTH'(23)}); // EXT=5: Row1=32, Row0=23

            // --------------------------------------------------------------------------------------------

            // ============================================================================
            // §6.6 NUM_ROWS SCALABILITY SANITY
            // Purpose: Verify the array operates correctly with NUM_ROWS=3 and
            //          no logic is hard-coded for NUM_ROWS=2.
            // Configuration:
            //   Row0 = [2,3]
            //   Row1 = [4,5]
            //   Row2 = [6,7]
            // Expected Row2 output at EXT=4 = 6*1 + 7*2 = 20.
            // ============================================================================

            $display("");
            $display("==================================================================");
            $display("§6.6 NUM_ROWS SCALABILITY");
            $display("==================================================================");

            rst_n = 0;
            activation_in = 0;
            load_compute_sel = 0;
            #1;
            rst_n = 1;
            #1;

            // Row0=[2,3], Row1=[4,5], Row2=[6,7]
            load_scale_weights({8'sd7,8'sd6,8'sd5,8'sd4,8'sd3,8'sd2});

            // Drive EXT=1,2,3,4 and check every scaled-array output.
            do_scale_compute(DATA_WIDTH'(1),
                    {ACC_WIDTH'(0), ACC_WIDTH'(0), ACC_WIDTH'(3)});
            do_scale_compute(DATA_WIDTH'(2),
                    {ACC_WIDTH'(0), ACC_WIDTH'(5), ACC_WIDTH'(8)});
            do_scale_compute(DATA_WIDTH'(3),
                    {ACC_WIDTH'(7), ACC_WIDTH'(14), ACC_WIDTH'(13)});
            do_scale_compute(DATA_WIDTH'(4),
                    {ACC_WIDTH'(20), ACC_WIDTH'(23), ACC_WIDTH'(18)});
            // ============================================================================

            $display("==================================================================");
            $display("TOTAL: %0d | PASSED: %0d | FAILED: %0d", tests, passed, failed);

            if (failed == 0)
                $display("REGRESSION: PASS");
            else
                $display("REGRESSION: FAIL");

            $display("==================================================================");

            #20 $finish;
        end
    endmodule
