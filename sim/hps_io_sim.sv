//
// hps_io_sim.sv
//
// Simulation stand-in for sys/hps_io.sv: no OSD (the status bits come
// from +status=), downloads, keys and the disk side of the sector
// interface are sim_top's ports, driven by the testbench.
//
module hps_io #(parameter CONF_STR = "", parameter WIDE = 0, parameter VDNUM = 1)
(
   input         clk_sys,
   inout  [45:0] HPS_BUS,
   inout  [21:0] gamma_bus,

   output [10:0] ps2_key,
   input   [2:0] ps2_kbd_led_use,
   input   [2:0] ps2_kbd_led_status,
   output [24:0] ps2_mouse,

   output [31:0] joystick_0,
   output [31:0] joystick_1,

   output [  1:0] buttons,
   output         forced_scandoubler,
   output [127:0] status,
   input  [ 15:0] status_menumask,

   output [VDNUM-1:0] img_mounted,
   output             img_readonly,
   output      [63:0] img_size,

   input       [31:0] sd_lba[VDNUM],
   input  [VDNUM-1:0] sd_rd,
   input  [VDNUM-1:0] sd_wr,
   output [VDNUM-1:0] sd_ack,
   output      [12:0] sd_buff_addr,
   output      [15:0] sd_buff_dout,
   input       [15:0] sd_buff_din[VDNUM],
   output             sd_buff_wr,

   output        ioctl_download,
   output [15:0] ioctl_index,
   output        ioctl_wr,
   output [26:0] ioctl_addr,
   output [15:0] ioctl_dout
);

assign buttons        = 0;
assign forced_scandoubler = 0;
assign gamma_bus[20:0] = 0;
// the OSD's settings: +status=HEX on the command line, all zero without
reg [127:0] status_arg = 0;
initial if(!$value$plusargs("status=%h", status_arg)) status_arg = 0;
// the HPS pulses the reset bit (status[0]) once the core is up; the core
// waits for its end (sys_ready)
reg [15:0] rst_cnt = 0;
always @(posedge clk_sys) if(rst_cnt != 16'hFFFF) rst_cnt <= rst_cnt + 1'd1;
wire hps_reset = rst_cnt > 16'd1000 && rst_cnt < 16'd3000;
// +rstcyc=N: the OSD's Reset (status[2]) for 2000 clocks from clock N
integer rst_cyc = 0, cyc = 0;
initial if(!$value$plusargs("rstcyc=%d", rst_cyc)) rst_cyc = 0;
always @(posedge clk_sys) cyc <= cyc + 1;
wire osd_reset = rst_cyc != 0 && cyc >= rst_cyc && cyc < rst_cyc + 2000;
assign status         = {status_arg[127:3], status_arg[2] | osd_reset, status_arg[1], status_arg[0] | hps_reset};
assign ioctl_download = sim_top.ioctl_download;
assign ioctl_index    = {8'd0, sim_top.ioctl_index};
assign ioctl_wr       = sim_top.ioctl_wr;
assign ioctl_addr     = sim_top.ioctl_addr;
assign ioctl_dout     = sim_top.ioctl_dout;
assign ps2_key        = sim_top.ps2_key;
assign joystick_0     = sim_top.joystick;
assign joystick_1     = 0;
assign ps2_mouse      = 0;

assign img_mounted    = sim_top.img_mounted;
assign img_readonly   = sim_top.img_readonly;
assign img_size       = {32'd0, sim_top.img_size};
assign sd_ack         = sim_top.sd_ack;
assign sd_buff_addr   = {5'd0, sim_top.sd_buff_addr};
assign sd_buff_dout   = sim_top.sd_buff_dout;
assign sd_buff_wr     = sim_top.sd_buff_wr;

endmodule
