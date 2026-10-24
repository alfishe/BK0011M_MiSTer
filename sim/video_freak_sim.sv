//
// video_freak_sim.sv
//
// Simulation stand-in for sys/video_freak.sv: no cropping, no scaling.
//
module video_freak
(
   input             CLK_VIDEO,
   input             CE_PIXEL,
   input             VGA_VS,
   input      [11:0] HDMI_WIDTH,
   input      [11:0] HDMI_HEIGHT,
   output            VGA_DE,
   output reg [12:0] VIDEO_ARX,
   output reg [12:0] VIDEO_ARY,

   input             VGA_DE_IN,
   input      [11:0] ARX,
   input      [11:0] ARY,
   input      [11:0] CROP_SIZE,
   input       [4:0] CROP_OFF,
   input       [2:0] SCALE
);

assign VGA_DE = VGA_DE_IN;
always @(posedge CLK_VIDEO) begin
   VIDEO_ARX <= {1'b0, ARX};
   VIDEO_ARY <= {1'b0, ARY};
end

endmodule
