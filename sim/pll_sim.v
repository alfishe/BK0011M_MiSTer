//
// pll_sim.v
//
// Simulation stand-in for rtl/pll.v: outclk_0 (clk_sys, 96 MHz) is the
// reference itself - the testbench clocks CLK_50M at the 96 MHz rate -
// and outclk_1 (CLK_VIDEO, 48 MHz) divides it by two.
//
module pll
(
   input      refclk,
   input      rst,
   output     outclk_0,
   output reg outclk_1 = 1'b0,
   output     locked
);

always @(posedge refclk) outclk_1 <= ~outclk_1;

assign outclk_0 = refclk;
assign locked   = ~rst;

endmodule
