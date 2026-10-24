//
// video_mixer_sim.sv
//
// Simulation stand-in for sys/video_mixer.sv: no scan doubler, no gamma,
// the core's video passes through on its pixel enable.  HALF_DEPTH colour
// inputs are 4 bits wide, as in the real one.
//
module video_mixer #(parameter LINE_LENGTH = 768, parameter HALF_DEPTH = 0, parameter GAMMA = 0)
(
   input            CLK_VIDEO,
   output reg       CE_PIXEL,
   input            ce_pix,

   input            scandoubler,
   input            hq2x,
   inout     [21:0] gamma_bus,

   input      [DW:0] R,
   input      [DW:0] G,
   input      [DW:0] B,
   input            HSync,
   input            VSync,
   input            HBlank,
   input            VBlank,

   input            HDMI_FREEZE,
   output           freeze_sync,

   output reg [7:0] VGA_R,
   output reg [7:0] VGA_G,
   output reg [7:0] VGA_B,
   output reg       VGA_VS,
   output reg       VGA_HS,
   output reg       VGA_DE
);

localparam DW = HALF_DEPTH ? 3 : 7;

assign freeze_sync = 1'b0;

wire [7:0] r8 = HALF_DEPTH ? {R, R} : R;
wire [7:0] g8 = HALF_DEPTH ? {G, G} : G;
wire [7:0] b8 = HALF_DEPTH ? {B, B} : B;

always @(posedge CLK_VIDEO) begin
   CE_PIXEL <= ce_pix;
   if(ce_pix) begin
      VGA_R  <= r8;
      VGA_G  <= g8;
      VGA_B  <= b8;
      VGA_HS <= HSync;
      VGA_VS <= VSync;
      VGA_DE <= ~(HBlank | VBlank);
   end
end

endmodule
