//
// monitor.sv
//
// Debug prints from inside the core: +busmon (every bus cycle the CPU
// gets answered, the first MAX_LINES), +fddmon (floppy controller
// accesses and sector transfers), +idemon (IDE register accesses).
//
module monitor;

localparam MAX_LINES = 400;

integer lines = 0, fdd_lines = 0, ide_lines = 0;
integer cycles = 0;
reg bus_on = 0, fdd_on = 0, ide_on = 0, trap_on = 0, fdd_wr_on = 0;   // +fddwr: every data register write
integer bus_from = 0;   // +busfrom=N: start the bus trace at clock N
integer bus_min = 0;    // +busmin=OCT: only addresses from here
initial begin
   bus_on  = $test$plusargs("busmon");
   if(!$value$plusargs("busfrom=%d", bus_from)) bus_from = 0;
   if(!$value$plusargs("busmin=%o", bus_min)) bus_min = 0;
   fdd_wr_on = $test$plusargs("fddwr");
   fdd_on  = $test$plusargs("fddmon") || fdd_wr_on;
   ide_on  = $test$plusargs("idemon");
   trap_on = $test$plusargs("trapmon");
end

// +rstmon: the reset chain, on every change
reg rst_on = 0;
initial rst_on = $test$plusargs("rstmon");
reg [4:0] old_rst = 0;
wire [4:0] rst_now = {sim_top.emu.sys_ready, sim_top.emu.cpu_dclo, sim_top.emu.cpu_aclo, sim_top.emu.bus_reset, sim_top.emu.cold_start};
always @(posedge sim_top.emu.clk_sys) begin
   old_rst <= rst_now;
   if(rst_on && old_rst != rst_now)
      $display("%0d RST sys_ready=%b dclo=%b aclo=%b init=%b cold=%b status=%h", cycles, rst_now[4], rst_now[3], rst_now[2], rst_now[1], rst_now[0], sim_top.emu.status);
end

// +cpumon: the CPU's bus pins on every change, the first MAX_LINES
reg cpu_on = 0;
initial cpu_on = $test$plusargs("cpumon");
integer cpu_lines = 0;
reg [20:0] old_pins = 0;
wire [20:0] pins = {sim_top.emu.bus_sync, sim_top.emu.bus_stb, sim_top.emu.cpu_din_out, sim_top.emu.cpu_dout_out, sim_top.emu.bus_we, sim_top.emu.bus_addr};
always @(posedge sim_top.emu.clk_sys) begin
   old_pins <= pins;
   if(cpu_on && cpu_lines < MAX_LINES && old_pins != pins) begin
      $display("%0d CPU sync=%b stb=%b din_stb=%b dout_stb=%b we=%b addr=%o dout=%o din=%o ack=%b", cycles, pins[20], pins[19], pins[18], pins[17], pins[16], pins[15:0],
               sim_top.emu.cpu_dout, sim_top.emu.cpu_din, sim_top.emu.cpu_ack);
      cpu_lines = cpu_lines + 1;
   end
end

// +palmon: every bus cycle to 177662/177663 (palette / keyboard register)
reg pal_on = 0;
initial pal_on = $test$plusargs("palmon");
reg old_pack = 0;
always @(posedge sim_top.emu.clk_sys) begin
   old_pack <= sim_top.emu.cpu_ack;
   if(pal_on && sim_top.emu.cpu_ack && !old_pack && sim_top.emu.bus_addr[15:1] == 15'o77731)
      $display("%0d PAL %s %o wtbt=%b din=%o pal=%h", cycles, sim_top.emu.bus_we ? "W" : "R", sim_top.emu.bus_addr,
               sim_top.emu.bus_wtbt, sim_top.emu.bus_din, sim_top.emu.video.pal);
end

reg [15:0] old_pal = 0;
always @(posedge sim_top.emu.clk_sys) begin
   old_pal <= sim_top.emu.video.pal;
   if(pal_on && old_pal != sim_top.emu.video.pal)
      $display("%0d PALCHG %h -> %h reg662=%o cswitch=%b", cycles, old_pal, sim_top.emu.video.pal, sim_top.emu.video.reg662, sim_top.emu.video.color_switch);
end

reg old_ack = 0;
always @(posedge sim_top.emu.clk_sys) begin
   cycles = cycles + 1;
   old_ack <= sim_top.emu.cpu_ack;
   if(bus_on && lines < MAX_LINES && cycles >= bus_from && sim_top.emu.bus_addr >= bus_min && sim_top.emu.cpu_ack && !old_ack) begin
      $display("%0d BUS %s %o = %o", cycles, sim_top.emu.bus_we ? "W" : "R", sim_top.emu.bus_addr,
               sim_top.emu.bus_we ? sim_top.emu.bus_din : sim_top.emu.cpu_din);
      lines = lines + 1;
   end
end

reg old_fstb = 0, old_istb = 0;
always @(posedge sim_top.emu.clk_sys) begin
   old_fstb <= sim_top.emu.bus_stb & sim_top.emu.fdc.sel;
   old_istb <= sim_top.emu.bus_stb & sim_top.emu.hdd.sel;
   if(fdd_on && sim_top.emu.bus_stb && sim_top.emu.fdc.sel && !old_fstb &&
      (sim_top.emu.bus_we ? !sim_top.emu.bus_addr[1] || fdd_lines < MAX_LINES || fdd_wr_on : !sim_top.emu.bus_addr[1] && fdd_lines < MAX_LINES)) begin
      $display("%0d FDD %s %o = %o trk=%0d sec=%0d", cycles, sim_top.emu.bus_we ? "W" : "R",
               sim_top.emu.bus_addr, sim_top.emu.bus_we ? sim_top.emu.bus_din : sim_top.emu.fdc.status,
               sim_top.emu.fdd.no_trk, sim_top.emu.fdd.no_sec);
      fdd_lines = fdd_lines + 1;
   end
   if(ide_on && sim_top.emu.bus_stb && sim_top.emu.hdd.sel && !old_istb && ide_lines < MAX_LINES &&
      (sim_top.emu.bus_addr[3:1] != 3'b111)) begin   // not the data register
      $display("%0d IDE %s %o = %o st=%0d", cycles, sim_top.emu.bus_we ? "W" : "R",
               sim_top.emu.bus_addr, sim_top.emu.bus_we ? ~sim_top.emu.bus_din :
               sim_top.emu.bus_addr[3:1] == 3'b000 ? {sim_top.emu.hdd.dar, sim_top.emu.hdd.status} :
               sim_top.emu.bus_addr[3:1] == 3'b001 ? {sim_top.emu.hdd.status, sim_top.emu.hdd.curheadreg} : 16'o177777, sim_top.emu.hdd.st);
      ide_lines = ide_lines + 1;
   end
end

reg old_rd = 0, old_wr = 0, old_hrd = 0, old_hwr = 0;
always @(posedge sim_top.emu.clk_sys) begin
   old_rd  <= sim_top.emu.fdd.read_sd;
   old_wr  <= sim_top.emu.fdd.wr_go;
   old_hrd <= sim_top.emu.hdd.sd_rd;
   old_hwr <= sim_top.emu.hdd.sd_wr;
   if(fdd_on && sim_top.emu.fdd.read_sd && !old_rd) $display("%0d FDD read  lba %0d", cycles, sim_top.emu.fdd_lba);
   if(fdd_on && sim_top.emu.fdd.wr_go   && !old_wr) $display("%0d FDD write lba %0d", cycles, sim_top.emu.fdd_lba);
   if(ide_on && sim_top.emu.hdd.sd_rd && !old_hrd) $display("%0d IDE read  lba %0d", cycles, sim_top.emu.hdd.sd_lba);
   if(ide_on && sim_top.emu.hdd.sd_wr && !old_hwr) $display("%0d IDE write lba %0d", cycles, sim_top.emu.hdd.sd_lba);
end

endmodule
