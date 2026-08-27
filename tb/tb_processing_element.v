`timescale 1ns/1ps
module tb_processing_element;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 20;

    reg                              clk;
    reg                              rst_n;
    reg                              load_compute_sel;
    reg  signed [DATA_WIDTH-1:0]     activation_in;
    reg  signed [DATA_WIDTH-1:0]     weight_in;
    reg  signed [ACC_WIDTH-1:0]      psum_in;
    wire signed [DATA_WIDTH-1:0]     activation_out;
    wire signed [ACC_WIDTH-1:0]      psum_out;
    wire                             overflow_flag;

    integer errors = 0;
    integer tests  = 0;
    integer passed = 0;
    integer failed = 0;

    processing_element #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_compute_sel(load_compute_sel),
        .activation_in(activation_in),
        .weight_in(weight_in),
        .psum_in(psum_in),
        .activation_out(activation_out),
        .psum_out(psum_out),
        .overflow_flag(overflow_flag)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_processing_element);
    end

    task report_case(input string name, input integer local_failures);
        begin
            tests = tests + 1;
            if (local_failures == 0) begin
                passed = passed + 1;
                $display("PASS %-30s", name);
            end
            else begin
                failed = failed + 1;
                $display("FAIL %-30s", name);
            end
        end
    endtask

    task load_weight(input signed [DATA_WIDTH-1:0] w, input string name);
        begin
            integer local_failures;
            local_failures = 0;

            load_compute_sel = 0;
            weight_in        = w;
            @(posedge clk);
            #1;

            // G3: activation_out is a registered pass-through that updates every cycle
            // regardless of load_compute_sel (WS-INT8 spec Sec 5, confirmed directly from
            // RTL: the assignment sits outside the load_compute_sel conditional). During a
            // load-mode cycle this task doesn't drive activation_in, so it holds whatever
            // the TB last set it to; activation_out must track that held value.
            if (activation_out !== activation_in) begin
                local_failures = local_failures + 1;
                errors = errors + 1;
                $display("FAIL G3 [t=%0t] (load_weight) activation_out=%0d expected=%0d (mode-independent pass-through)",
                          $time, activation_out, activation_in);
            end

            report_case(name, local_failures);
        end
    endtask

    task do_compute(
        input signed [DATA_WIDTH-1:0] act,
        input signed [ACC_WIDTH-1:0]  pin,
        input signed [ACC_WIDTH-1:0]  expected_psum,
        input                         expected_ovf,
        input string                  name
    );
        begin
            integer local_failures;
            local_failures = 0;

            load_compute_sel = 1;
            activation_in    = act;
            psum_in          = pin;
            @(posedge clk);
            #1;

            if (activation_out !== act) begin
                local_failures = local_failures + 1;
                errors = errors + 1;
                $display("FAIL [t=%0t] activation_out=%0d expected=%0d",
                          $time, activation_out, act);
            end
            if (psum_out !== expected_psum) begin
                local_failures = local_failures + 1;
                errors = errors + 1;
                $display("FAIL [t=%0t] act=%0d wt=%0d psum_in=%0d -> psum_out=%0d expected=%0d",
                          $time, act, dut.weight_reg, pin, psum_out, expected_psum);
            end
            if (overflow_flag !== expected_ovf) begin
                local_failures = local_failures + 1;
                errors = errors + 1;
                $display("FAIL [t=%0t] overflow_flag=%0b expected=%0b",
                          $time, overflow_flag, expected_ovf);
            end

            report_case(name, local_failures);
        end
    endtask

    initial begin
        integer local_failures;
        local_failures = 0;

        clk               = 0;
        rst_n             = 0;
        load_compute_sel  = 0;
        activation_in     = 0;
        weight_in         = 0;
        psum_in           = 0;

        #12 rst_n = 1;

        // Positive x positive baseline, weight reused across two computes (weight-stationary check)
        load_weight(5, "BASELINE_W5");
        do_compute(3, 2, 17, 1'b0, "BASELINE_P1");
        do_compute(4, 10, 30, 1'b0, "BASELINE_P2");

        // Weight reload, positive x positive
        load_weight(9, "RELOAD_W9");
        do_compute(6, 100, 154, 1'b0, "RELOAD_P1");

        // Negative weight x positive activation
        load_weight(-5, "NEGWT_POSACT");
        do_compute(3, 100, 85, 1'b0, "NEGWT_POSACT_P1");

        // Positive weight x negative activation
        load_weight(9, "POSWT_NEGACT");
        do_compute(-6, 50, -4, 1'b0, "POSWT_NEGACT_P1");

        // Negative weight x negative activation
        load_weight(-9, "NEGWT_NEGACT");
        do_compute(-6, -100, -46, 1'b0, "NEGWT_NEGACT_P1");

        // Positive-direction overflow: psum_in at max representable value plus a positive product
        load_weight(100, "OVF_POS_LOAD");
        do_compute(100, 524287, -514289, 1'b1, "OVF_POS");

        // Negative-direction overflow (underflow): psum_in at min representable value plus a negative product
        load_weight(-100, "OVF_NEG_LOAD");
        do_compute(100, -524288, 514288, 1'b1, "OVF_NEG");

        // G1: Reset mid-stream, from a genuinely non-zero state.
        rst_n = 0;
        #1;
        local_failures = 0;
        if (dut.weight_reg !== 0 || activation_out !== 0 || psum_out !== 0 || overflow_flag !== 1'b0) begin
            local_failures = 1;
            errors = errors + 1;
            $display("FAIL G1 [t=%0t] reset mid-stream: weight_reg=%0d activation_out=%0d psum_out=%0d overflow_flag=%0b (expected all 0)",
                      $time, dut.weight_reg, activation_out, psum_out, overflow_flag);
        end
        rst_n = 1;
        report_case("G1_RESET_MIDSTREAM", local_failures);

        // G2: Post-reset functional recovery.
        load_weight(7, "G2_RECOVERY_LOAD");
        do_compute(4, 0, 28, 1'b0, "G2_RECOVERY_COMPUTE");

        // G4-G10 set
        load_weight(1, "G4_POS_EDGE_LOAD");
        do_compute(1, 524286, 524287, 1'b0, "G4_POS_EDGE");

        load_weight(1, "G5_POS_OVF_LOAD");
        do_compute(1, 524287, -524288, 1'b1, "G5_POS_OVF");
        do_compute(0, 0, 0, 1'b0, "G10_FLAG_CLEAR");

        load_weight(0, "G6_NEG_EDGE_LOAD");
        do_compute(0, -524288, -524288, 1'b0, "G6_NEG_EDGE");

        load_weight(-1, "G7_NEG_OVF_LOAD");
        do_compute(1, -524288, 524287, 1'b1, "G7_NEG_OVF");

        load_weight(-128, "G8_MINPROD_LOAD");
        do_compute(-128, 0, 16384, 1'b0, "G8_MINPROD");

        load_weight(127, "G9_MIXEDPROD_LOAD");
        do_compute(-128, 0, -16256, 1'b0, "G9_MIXEDPROD");

        // G11-G16 set
        load_weight(0, "G11_ZERO_W_LOAD");
        do_compute(50, 7, 7, 1'b0, "G11_ZERO_W");

        load_weight(50, "G12_ZERO_A_LOAD");
        do_compute(0, 7, 7, 1'b0, "G12_ZERO_A");

        load_weight(0, "G13_ZERO_BOTH_LOAD");
        do_compute(0, 0, 0, 1'b0, "G13_ZERO_BOTH");

        load_weight(5, "G14_FIRST_ACC_LOAD");
        do_compute(3, 0, 15, 1'b0, "G14_FIRST_ACC");

        load_weight(3, "G15_REUSE_LOAD");
        do_compute(1, 0, 3, 1'b0, "G15_REUSE_1");
        do_compute(2, 0, 6, 1'b0, "G15_REUSE_2");
        do_compute(3, 0, 9, 1'b0, "G15_REUSE_3");
        do_compute(4, 0, 12, 1'b0, "G15_REUSE_4");
        do_compute(5, 0, 15, 1'b0, "G15_REUSE_5");

        // G16: back-to-back load_weight calls, no intervening compute.
        load_weight(11, "G16_BACK2BACK_1");
        load_weight(22, "G16_BACK2BACK_2");
        local_failures = 0;
        if (dut.weight_reg !== 22) begin
            local_failures = 1;
            errors = errors + 1;
            $display("FAIL G16 [t=%0t] weight_reg=%0d expected=22 after back-to-back loads (no intervening compute)",
                      $time, dut.weight_reg);
        end
        report_case("G16_BACK2BACK_WEIGHT", local_failures);
        do_compute(2, 0, 44, 1'b0, "G16_BACK2BACK_COMPUTE");

        $display("TOTAL: %0d | PASSED: %0d | FAILED: %0d", tests, passed, failed);
        if (failed == 0)
            $display("REGRESSION: PASS");
        else
            $display("REGRESSION: FAIL");

        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d / %0d TESTS FAILED", errors, tests);

        #20 $finish;
    end

endmodule
