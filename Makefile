.PHONY: sim sim_row wave lint synth clean
TOP    = tb_processing_element
RTL    = rtl/processing_element.v
TB     = tb/tb_processing_element.v
OUT    = sim/obj_dir
YOSYS_OUT = build/yosys

sim:
	verilator --binary --trace -Wall -Wno-SYNCASYNCNET --top-module $(TOP) $(RTL) $(TB) -o sim_pe -Mdir $(OUT)
	./$(OUT)/sim_pe
sim_row:
	verilator --binary --trace -Wall -Wno-SYNCASYNCNET -Wno-WIDTHEXPAND --top-module tb_pe_row rtl/processing_element.v rtl/pe_row.v tb/tb_pe_row.v -o sim_row -Mdir sim/obj_dir_row
	./sim/obj_dir_row/sim_row
wave:
	gtkwave dump.vcd

lint:
	verilator --lint-only -Wall $(RTL)

synth:
	mkdir -p $(YOSYS_OUT)
	yosys -s yosys/synth.ys

clean:
	rm -rf $(OUT) $(YOSYS_OUT) dump.vcd
