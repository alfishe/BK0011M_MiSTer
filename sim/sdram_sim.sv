//
// sdram_sim.sv
//
// Simulation stand-in for rtl/sdram.sv: the same ports, a 4 MB array
// instead of the chip, one clock of read latency.  Byte order on odd
// addresses and the 8-bit (wtbt = 0) write mode as the real one.
//
module sdram
(
   input             init,
   input             clk,
   inout      [15:0] SDRAM_DQ,
   output     [12:0] SDRAM_A,
   output            SDRAM_DQML,
   output            SDRAM_DQMH,
   output      [1:0] SDRAM_BA,
   output            SDRAM_nCS,
   output            SDRAM_nWE,
   output            SDRAM_nRAS,
   output            SDRAM_nCAS,
   output            SDRAM_CKE,
   output            SDRAM_CLK,

   input       [1:0] wtbt,
   input      [24:0] addr,
   output     [15:0] dout,
   input      [15:0] din,
   input             we,
   input             rd,
   output reg        ready = 1'b1
);

assign SDRAM_DQ = 16'bZ;
assign {SDRAM_A, SDRAM_DQML, SDRAM_DQMH, SDRAM_BA, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK} = 0;

localparam WORDS = 1 << 21;   // 4 MB

reg [15:0] mem[0:WORDS-1];
reg [24:0] save_addr = 0;
reg [15:0] data = 0;
reg        old_we = 0, old_rd = 0;

assign dout = save_addr[0] ? {data[7:0], data[15:8]} : data;

always @(posedge clk) begin
   old_we <= we;
   old_rd <= rd;
   if(we & ~old_we) begin
      save_addr <= addr;
      if(wtbt == 2'b00) begin
         if(addr[0]) mem[addr[24:1]][15:8] <= din[7:0];
         else        mem[addr[24:1]][7:0]  <= din[7:0];
      end else begin
         if(wtbt[0]) mem[addr[24:1]][7:0]  <= din[7:0];
         if(wtbt[1]) mem[addr[24:1]][15:8] <= din[15:8];
      end
   end
   if(rd & ~old_rd) begin
      save_addr <= addr;
      data      <= mem[addr[24:1]];
   end
end

endmodule
