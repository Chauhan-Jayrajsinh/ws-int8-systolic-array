`timescale 1ns/1ps
// ============================================================================
// pe_row.v -- Row of NUM_PE weight-stationary processing elements
// IP block: Systolic Array for AI Accelerators -- Week 3
//
// Design Decisions (fill in as you implement -- see pe_row_spec.md Sec 8):
//   - Activation distribution (Sec 4.2):
//   - First PE's incoming psum (Sec 4.3):
//   - weight_in_flat bit-slice convention (Sec 5):
//   - Overflow combining logic (Sec 4.5):
//
// Reuse constraint (Sec 4.1): this module MUST instantiate processing_element
// for all MAC logic. Do not write a multiply or accumulate here -- if you
// find yourself doing that, stop, that logic belongs in processing_element
// and already exists there.
// ============================================================================

module pe_row #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 20,
    parameter NUM_PE     = 3
)(
    input                                   clk,
    input                                   rst_n,
    input                                   load_compute_sel,
    input  signed [DATA_WIDTH-1:0]          activation_in,
    input  signed [NUM_PE*DATA_WIDTH-1:0]   weight_in_flat,
    output signed [ACC_WIDTH-1:0]           psum_out,
    output                                  overflow_flag
);

    // ------------------------------------------------------------------
    // TODO 1: Declare whatever internal wires you need to:
    //   - carry each PE's weight slice out of weight_in_flat
    //   - chain psum from PE i-1 into PE i (think about how many wires
    //     you need for a chain of NUM_PE stages, including the "input"
    //     to PE 0 and the "output" of the last PE)
    //   - collect each PE's individual overflow_flag for combining
    //
    // e.g. (fill in / adjust as needed):
    // wire signed [ACC_WIDTH-1:0] psum_chain [0:NUM_PE];
    // wire                        pe_overflow [0:NUM_PE-1];
    // wire signed [DATA_WIDTH-1:0] pe_activation_out [0:NUM_PE-1]; // unused for broadcast, but ports need a sink
    // ------------------------------------------------------------------

    wire signed [ACC_WIDTH-1:0] psum_chain [0:NUM_PE];
    wire [NUM_PE-1:0] pe_overflow;
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [DATA_WIDTH-1:0] pe_activation_out [0:NUM_PE-1];
    /* verilator lint_on UNUSEDSIGNAL */
    

    // ------------------------------------------------------------------
    // TODO 2: generate block instantiating NUM_PE copies of processing_element.
    // Design must not hardcode NUM_PE anywhere -- use the parameter.
    //
    // For each PE i, decide and connect:
    //   .activation_in  -- per Sec 4.2: work out on paper what every PE
    //                      should see on a given cycle before wiring this
    //   .weight_in      -- the correct DATA_WIDTH-bit slice of weight_in_flat,
    //                      per YOUR OWN documented bit-slicing convention
    //   .psum_in        -- per Sec 4.3: what does PE 0 start from? what
    //                      feeds PE i>0?
    //   .psum_out       -- feeds into psum_chain / the row output
    //   .overflow_flag  -- feeds into your overflow-collecting wire(s)
    //   .activation_out -- must connect to something even though row
    //                      broadcast doesn't use it for chaining
    //
    assign psum_chain[0] = '0;
    genvar i;
    generate
      for (i = 0; i < NUM_PE; i = i + 1) begin : pe_inst
        processing_element #(
          .DATA_WIDTH(DATA_WIDTH),
          .ACC_WIDTH(ACC_WIDTH)
        ) pe (
          .clk(clk),
          .rst_n(rst_n),
          .load_compute_sel(load_compute_sel),
          .activation_in(activation_in), 
          .weight_in(weight_in_flat[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i]),
          .psum_in(psum_chain[i]),
          .activation_out(pe_activation_out[i]),
          .psum_out(psum_chain[i+1]),
          .overflow_flag(pe_overflow[i])
        );
      end
    endgenerate
    // ------------------------------------------------------------------


    // ------------------------------------------------------------------
    // TODO 3: Drive the row-level outputs.
    //   psum_out      = the LAST PE's psum_out (the row result)
    //   overflow_flag = Sec 4.5 combining logic across all NUM_PE flags
    //                   (there's a standard bitwise op for "any of N bits
    //                   set" -- pick it and be able to justify it for any
    //                   NUM_PE, not just 3)
    // ------------------------------------------------------------------

    assign psum_out = psum_chain[NUM_PE];
    assign overflow_flag = |pe_overflow;

endmodule
