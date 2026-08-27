`timescale 1ns/1ps
// ============================================================================
// tb_pe_row.v -- Directed testbench for pe_row
// Verification Plan (pe_row_spec.md Sec 6) -- implement all 5 categories:
//   1. Basic correctness
//   2. Weight reload mid-sequence
//   3. Overflow
//   4. Reset mid-stream
//   5. Timing check against your own Sec 4.4 cycle-by-cycle table
//
// RULE (same discipline as tb_processing_element.v): every expected value
// below must be computed BY HAND, before you run the simulator. Build your
// Sec 4.4 timing table first, then derive stimulus + expected psum_out /
// overflow_flag from it. A test whose expected value you compute after
// seeing simulator output isn't verifying anything.
// ============================================================================

module tb_pe_row;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 20;
    parameter NUM_PE     = 3;

    reg                                  clk;
    reg                                  rst_n;
    reg                                  load_compute_sel;
    reg  signed [DATA_WIDTH-1:0]         activation_in;
    reg  signed [NUM_PE*DATA_WIDTH-1:0]  weight_in_flat;
    wire signed [ACC_WIDTH-1:0]          psum_out;
    wire                                 overflow_flag;

    integer tests  = 0;
    integer passed = 0;
    integer failed = 0;

    pe_row #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .NUM_PE(NUM_PE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_compute_sel(load_compute_sel),
        .activation_in(activation_in),
        .weight_in_flat(weight_in_flat),
        .psum_out(psum_out),
        .overflow_flag(overflow_flag)
    );

    

    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump_pe_row.vcd");
        $dumpvars(0, tb_pe_row);
    end

    task report_case(input string name, input reg local_failures);
        begin
            tests = tests + 1;
            if (local_failures == 0) begin
                passed = passed + 1;
                $display("PASS %-30s", name);
            end else begin
                failed = failed + 1;
                $display("FAIL %-30s", name);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // TODO 1: load_row_weights task.
    // Pack NUM_PE signed weights into weight_in_flat using YOUR bit-slicing
    // convention -- it must match exactly what you wired in pe_row.v's
    // generate block. A mismatch here is the classic self-inflicted bug
    // the spec calls out: DUT and TB silently disagreeing on convention.
    //
    // Signature to implement (adjust arg count/style if you prefer an
    // array instead of separate w0/w1/w2 args -- your call, but document it):
    //
    task load_row_weights(
    input signed [NUM_PE*DATA_WIDTH-1:0] weights
);
    begin
        load_compute_sel = 0;
        weight_in_flat   = weights;

        @(posedge clk);
        #1;
    end
endtask
    // ------------------------------------------------------------------


    // ------------------------------------------------------------------
    // TODO 2: do_compute task -- drive one activation_in value for one
    // cycle in compute mode, then self-check psum_out and overflow_flag
    // against hand-derived expected values. Same pass/fail + report_case
    // pattern as tb_processing_element.v's do_compute.
    // ------------------------------------------------------------------
    task do_compute(
        input signed [DATA_WIDTH-1:0] act,
        input signed [ACC_WIDTH-1:0]  expected_psum,
        input                         expected_ovf,
        input string                  name
    );
    reg local_failures;

    begin
        load_compute_sel  = 1;   
        activation_in     = act;
        @(posedge clk);
        #1;

        local_failures = (psum_out !== expected_psum ||
                          overflow_flag !== expected_ovf);

        if (local_failures) begin
            $display("ACTUAL: psum_out=%0d, overflow_flag=%0b",
                     psum_out, overflow_flag);
            $display("EXPECT: psum_out=%0d, overflow_flag=%0b",
                     expected_psum, expected_ovf);
        end
        report_case(name, local_failures);
    end
    endtask
    // ------------------------------------------------------------------
    task reset_dut;
    begin
        rst_n = 1'b0;
        #1;
        rst_n = 1'b1;
        #1;
    end
    endtask

    initial begin
        clk               = 0;
        rst_n             = 0;
        load_compute_sel  = 0;
        activation_in     = 0;
        weight_in_flat    = 0;

        #12 rst_n = 1;  // reset is released at 12 ns

        // ------------------------------------------------------------
        // TEST 1: Basic correctness (Sec 6.1)
        // Pick small weights (e.g. w0,w1,w2) and a short known sequence
        // x[1..N]. Hand-calculate expected psum_out for each cycle from
        // your Sec 4.4 timing table BEFORE writing the do_compute() calls.
        // ------------------------------------------------------------
        load_row_weights({8'sd4, 8'sd3, 8'sd2});

        do_compute(1,  4, 1'b0, "Basic x1");
        do_compute(2, 11, 1'b0, "Basic x2");
        do_compute(-1, 4, 1'b0, "Basic x3");

        // ------------------------------------------------------------
        // TEST 2: Weight reload mid-sequence (Sec 6.2)
        // Confirm reloading weights mid-stream changes subsequent outputs
        // correctly and does not corrupt in-flight partial sums.
        // ------------------------------------------------------------

        load_row_weights({8'sd4, 8'sd3, 8'sd2});

        do_compute(1,  5,  1'b0, "Reload x1");
        do_compute(2,  9,  1'b0, "Reload x2");

        load_row_weights({8'sd7, 8'sd6, 8'sd5});

        do_compute(1, 15, 1'b0, "Reload x3");
        do_compute(2, 24, 1'b0, "Reload x4");
        do_compute(-1, 10, 1'b0, "Reload x5");

        // ------------------------------------------------------------
        // TEST 3: Overflow boundary / non-overflow confirmation (Sec 6.3)
        // NUM_PE=3, ACC_WIDTH=20: max achievable |psum| = 3 x 16384 = 49152,
        // far below the +-524288 signed range -> overflow_flag must stay 0
        // at both sign-direction magnitude extremes. This is the correct
        // result for this configuration, not a test gap.
        // ------------------------------------------------------------

        reset_dut();

        load_row_weights({-8'sd128, -8'sd128, -8'sd128});

        do_compute(-128, 16384,  1'b0, "MAXPOS_C1");
        do_compute(-128, 32768,  1'b0, "MAXPOS_C2");
        do_compute(-128, 49152,  1'b0, "MAXPOS_C3");
        do_compute(-128, 49152,  1'b0, "MAXPOS_C4");

        reset_dut();

        load_row_weights({8'sd127, 8'sd127, 8'sd127});

        do_compute(-128, -16256, 1'b0, "MAXNEG_C1");
        do_compute(-128, -32512, 1'b0, "MAXNEG_C2");
        do_compute(-128, -48768, 1'b0, "MAXNEG_C3");
        do_compute(-128, -48768, 1'b0, "MAXNEG_C4");

                    
        // ------------------------------------------------------------
        // TEST 4: Reset mid-stream (Sec 6.4)
        // Assert rst_n mid-stream; confirm the row returns to a known,
        // documented state (decide + state what that state is).
        // Reset state: psum_out=0, overflow_flag=0.
        // ------------------------------------------------------------
        
        reset_dut();
        load_row_weights({8'sd4, 8'sd3, 8'sd2});

        do_compute(1,  4, 1'b0, "Reset x1");
        do_compute(2,  11, 1'b0, "Reset x2");

        // Assert reset mid-stream
        rst_n = 1'b0;
        #1;

        if (psum_out !== 0 || overflow_flag !== 1'b0)
            $display("FAIL Reset state");
        else
            $display("PASS Reset state");
        
        // Release reset
        rst_n = 1'b1;
        #1;
        
        // Weights were cleared by reset → reload them
        load_row_weights({8'sd4, 8'sd3, 8'sd2});
        // Verify computation restarts from clean state
        do_compute(1, 4, 1'b0, "Reset x3");
        do_compute(2, 11, 1'b0, "Reset x4");


        // ------------------------------------------------------------
        // TEST 5: Timing check against your Sec 4.4 table (Sec 6.5)
        // This is the test that catches an RTL/testbench boundary bug,
        // not just an obviously-wrong final number -- check psum_out on
        // EVERY cycle (including load-phase and warm-up cycles), not just
        // at steady state.
        // ------------------------------------------------------------

        reset_dut();

        load_row_weights({8'sd4, 8'sd3, 8'sd2});

        // During weight loading, no MAC operation occurs.
        // Reset state remains visible at the row output.
        if (psum_out !== 0 || overflow_flag !== 1'b0) begin
            $display("FAIL Timing LOAD: psum_out=%0d, overflow_flag=%0b",
                     psum_out, overflow_flag);
            failed = failed + 1;
        end
        else begin
            $display("PASS Timing LOAD");
            passed = passed + 1;
        end
        tests = tests + 1;
        // Check every compute cycle against the timing table
        // COMPUTE CYCLES
        do_compute(1,  4,  1'b0, "Timing C1");
        do_compute(2, 11,  1'b0, "Timing C2");
        do_compute(-1, 4,  1'b0, "Timing C3");
        do_compute(0,  1,  1'b0, "Timing C4");
        do_compute(1,  2,  1'b0, "Timing C5");
        do_compute(2, 11,  1'b0, "Timing C6");


        // ------------------------------------------------------------
        $display("TOTAL: %0d | PASSED: %0d | FAILED: %0d", tests, passed, failed);
        if (failed == 0)
            $display("REGRESSION: PASS");
        else
            $display("REGRESSION: FAIL");

        #20 $finish;
    end

endmodule
