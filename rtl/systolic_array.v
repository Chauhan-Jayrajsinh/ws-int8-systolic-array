`timescale 1ns/1ps
// ============================================================================
// systolic_array.v -- 2D array of NUM_ROWS pe_row instances, row-to-row
// nearest-neighbor activation relay (hybrid systolic architecture, B1)
// IP block: Systolic Array for AI Accelerators -- 2D Array Milestone
//
// Design Decisions (fill in as you implement -- see systolic_array_spec.md Sec 8):
//   - Row-to-row relay direction/register count (Sec 4.2):
//   - pe_row.v activation_out port source (Sec 4.2):
//   - weight_in_flat row-major slicing convention (Sec 2):
//   - Per-row vs array-wide overflow reporting (Sec 4.5):
//
// Reuse constraint (Sec 4.1): this module MUST instantiate pe_row for all
// row-level MAC/chaining logic. Do not write a psum chain or multiply here.
//
// PREREQUISITE: pe_row.v must first gain an `activation_out` port (registered
// pass-through of its own broadcast activation_in) before this module can be
// wired up -- see systolic_array_spec.md Sec 4.2. That is a small, additive
// change to pe_row.v itself and is NOT part of this file. Do it there first,
// re-run the full pe_row regression (27/27 expected, unchanged), THEN come
// back to this skeleton.
// ============================================================================

module systolic_array #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 20,
    parameter NUM_PE     = 3,   // columns per row (reduction depth, passed through to pe_row)
    parameter NUM_ROWS   = 3    // rows (new dimension -- the systolic relay axis)
)(
    input                                            clk,
    input                                             rst_n,
    input                                             load_compute_sel,
    input  signed [DATA_WIDTH-1:0]                    activation_in,        // external stream, enters row 0 only
    input  signed [NUM_ROWS*NUM_PE*DATA_WIDTH-1:0]    weight_in_flat,       // row-major, see Sec 2
    output signed [NUM_ROWS*ACC_WIDTH-1:0]            psum_out_flat,        // one ACC_WIDTH slice per row
    output [NUM_ROWS-1:0]                             overflow_flag_flat   // one bit per row
);

    // ------------------------------------------------------------------
    // TODO 1: Declare internal wires you need to:
    //   - relay activation from row r-1 into row r (NUM_ROWS-1 relay wires,
    //     or an array sized [0:NUM_ROWS-1] / [0:NUM_ROWS] -- your call, but
    //     be precise about which index means "row r's input" vs "row r's
    //     own registered output")
    //   - collect each row's psum_out and overflow_flag before packing them
    //     into the flat output buses
    //
    // Remember: row 0's activation input is the EXTERNAL activation_in port
    // directly (Sec 2), not a relayed signal -- only rows 1..NUM_ROWS-1 are
    // fed by relay.
    // ------------------------------------------------------------------

    wire signed [DATA_WIDTH-1:0] activation_relay [0:NUM_ROWS]; // relay wire array, row 0 is external input
    wire signed [ACC_WIDTH-1:0] psum_out_row [0:NUM_ROWS-1]; // one slice per row

    // ------------------------------------------------------------------
    // TODO 2: generate block instantiating NUM_ROWS copies of pe_row.
    // Design must not hardcode NUM_ROWS (or NUM_PE) anywhere.
    //
    // For each row r, decide and connect:
    //   .activation_in   -- external activation_in for r==0, else the
    //                       relayed activation_out from row r-1 (Sec 4.2)
    //   .weight_in_flat  -- the correct NUM_PE*DATA_WIDTH-bit slice of the
    //                       array-level weight_in_flat, per YOUR documented
    //                       row-major convention (Sec 2) -- make sure this
    //                       matches your testbench's packing exactly, same
    //                       self-inflicted-bug warning as pe_row_spec.md Sec 5
    //   .psum_out        -- feeds into this row's slice of psum_out_flat
    //   .overflow_flag   -- feeds into this row's bit of overflow_flag_flat
    //   .activation_out  -- the NEW pe_row port (Sec 4.2 prerequisite) --
    //                       feeds the NEXT row's activation_in. The last
    //                       row's activation_out is unused by this array
    //                       but the port still needs a sink.
    // ------------------------------------------------------------------
    assign activation_relay[0] = activation_in;

    genvar r;
    generate
        for (r=0; r < NUM_ROWS; r = r + 1) begin : row_inst
            pe_row #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .NUM_PE(NUM_PE)
            ) row (
                .clk(clk),
                .rst_n(rst_n),
                .load_compute_sel(load_compute_sel),
                .activation_in(activation_relay[r]),
                .weight_in_flat(weight_in_flat[(r+1)*NUM_PE*DATA_WIDTH-1 -: NUM_PE*DATA_WIDTH]),
                .psum_out(psum_out_row[r]),
                .overflow_flag(overflow_flag_flat[r]),
                .activation_out(activation_relay[r+1])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // TODO 3: Pack per-row psum_out and overflow_flag signals into the
    // flat output buses, matching the row-major convention you documented
    // in Sec 2/Sec 8.
    // ------------------------------------------------------------------

    genvar i;
    generate
        for (i=0; i < NUM_ROWS; i = i + 1) begin : pack_out
            assign psum_out_flat[(i+1)*ACC_WIDTH-1 -: ACC_WIDTH] = psum_out_row[i];
        end
    endgenerate
endmodule
