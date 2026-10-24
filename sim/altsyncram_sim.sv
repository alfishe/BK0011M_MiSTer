//
// altsyncram_sim.sv
//
// Simulation stand-in for the Altera altsyncram used by the bios ROM in
// rtl/memory.sv (simple dual port, 16 x 65536): the ROM image comes from
// bios.hex (made from rtl/bios.mif by mif2hex.py) instead of the .mif.
//
module altsyncram #(parameter width_a = 16, widthad_a = 16, numwords_a = 65536,
                    width_b = 16, widthad_b = 16, numwords_b = 65536,
                    init_file = "", intended_device_family = "", lpm_type = "",
                    operation_mode = "", outdata_reg_b = "", address_aclr_b = "",
                    address_reg_b = "", clock_enable_input_a = "", clock_enable_input_b = "",
                    clock_enable_output_b = "", outdata_aclr_b = "", power_up_uninitialized = "",
                    read_during_write_mode_mixed_ports = "", width_byteena_a = 1)
(
   input  [widthad_a-1:0] address_a,
   input  [widthad_b-1:0] address_b,
   input                  clock0,
   input                  clock1,
   input  [width_a-1:0]   data_a,
   input  [width_b-1:0]   data_b,
   input                  wren_a,
   input                  wren_b,
   input                  rden_a,
   input                  rden_b,
   input                  aclr0, aclr1, addressstall_a, addressstall_b, clocken0, clocken1, clocken2, clocken3,
   input                  byteena_a, byteena_b,
   output [width_a-1:0]   q_a,
   output reg [width_b-1:0] q_b,
   output                 eccstatus
);

reg [width_a-1:0] mem[0:numwords_a-1];
initial $readmemh("bios.hex", mem);

always @(posedge clock0) begin
   if(wren_a) mem[address_a] <= data_a;
   q_b <= mem[address_b];
end

assign q_a = 0;
assign eccstatus = 0;

endmodule
