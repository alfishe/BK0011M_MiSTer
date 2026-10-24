# Model of the core for Verilator: make, then obj_dir/Vsim_top frames every [options]
# Run from this directory: the ROM (bios.hex) and the floppy track template
# (rtl/fdd/rawtrk.hex) are read relative to it.

RTL = ../rtl
SRC = sim_top.sv monitor.sv hps_io_sim.sv video_mixer_sim.sv video_freak_sim.sv pll_sim.v sdram_sim.sv altsyncram_sim.sv \
      ../BK0011M.sv $(RTL)/memory.sv $(RTL)/video.sv $(RTL)/keyboard.sv $(RTL)/translate.v \
      $(RTL)/disk.sv $(RTL)/ym2149.sv $(RTL)/fdd/vp1_128.sv $(RTL)/fdd/fdd4.v $(RTL)/ide/smk_ide.sv \
      vm1_plm_sim.v $(RTL)/VM1/vm1_qbus_se.sv $(RTL)/VM1/vm1_se.v $(RTL)/VM1/vm1_tve.v $(RTL)/VM1/vm1_vic.v

VFLAGS = --cc --exe --build -O3 -j 0 --top-module sim_top -I. -I.. \
         -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINMISSING -Wno-PINCONNECTEMPTY \
         -Wno-DECLFILENAME -Wno-UNDRIVEN -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN \
         -Wno-TIMESCALEMOD -Wno-COMBDLY -Wno-CASEX -Wno-UNOPTFLAT -Wno-LATCH -Wno-PROCASSWIRE \
         -CFLAGS -O2

all: obj_dir/Vsim_top bios.hex

build_id.v:
	echo '`define BUILD_DATE "000000"' > build_id.v

vm1_plm_sim.v: $(RTL)/VM1/vm1_plm.v gen_plm_sim.py
	python3 gen_plm_sim.py

obj_dir/Vsim_top: $(SRC) sim_main.cpp build_id.v
	verilator $(VFLAGS) $(SRC) sim_main.cpp

bios.hex: $(RTL)/bios.mif mif2hex.py
	python3 mif2hex.py

clean:
	rm -rf obj_dir *.ppm

.PHONY: all clean
