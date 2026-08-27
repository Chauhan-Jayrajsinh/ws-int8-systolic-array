`timescale 1ns/1ps
module processing_element #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 20   // 2*DATA_WIDTH(16) + ceil(log2(16))=4 -> 20
  )(
    input                                clk,
    input                                rst_n,
    input                                load_compute_sel,   // 0 = load weight, 1 = compute
    input      signed [DATA_WIDTH-1:0]   activation_in,
    input      signed [DATA_WIDTH-1:0]   weight_in,
    input      signed [ACC_WIDTH-1:0]    psum_in,
    output reg signed [DATA_WIDTH-1:0]   activation_out,
    output reg signed [ACC_WIDTH-1:0]    psum_out,
    output reg                           overflow_flag
  );

  reg  signed [DATA_WIDTH-1:0]     weight_reg;
  wire signed [2*DATA_WIDTH-1:0]   mult_result;   // signed x signed product, fits in 2*DATA_WIDTH bits
  wire signed [ACC_WIDTH:0]        sum_result;    // +1 guard bit, used for signed-overflow check

  assign mult_result = activation_in * weight_reg;

  // Sign-extend psum_in and mult_result to ACC_WIDTH+1 bits before adding (was zero-extension)
  assign sum_result  = {psum_in[ACC_WIDTH-1], psum_in} +
         {{(ACC_WIDTH - 2*DATA_WIDTH + 1){mult_result[2*DATA_WIDTH-1]}}, mult_result};

  always @(posedge clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      weight_reg     <= {DATA_WIDTH{1'b0}};
      activation_out <= {DATA_WIDTH{1'b0}};
      psum_out       <= {ACC_WIDTH{1'b0}};
      overflow_flag  <= 1'b0;
    end
    else
    begin
      activation_out <= activation_in;

      if (!load_compute_sel)
      begin
        weight_reg <= weight_in;
      end
      else
      begin
        psum_out      <= sum_result[ACC_WIDTH-1:0];
        // Signed overflow: guard bit vs. sign bit of truncated result disagree (was carry-out check)
        overflow_flag <= (sum_result[ACC_WIDTH] != sum_result[ACC_WIDTH-1]);
      end
    end
  end

endmodule 
