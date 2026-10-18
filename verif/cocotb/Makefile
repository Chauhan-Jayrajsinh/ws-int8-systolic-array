# Makefile -- Cocotb harness for systolic_array
# Standard cocotb Makefile-based flow. Run with: make
# Requires: pip install cocotb cocotb-test (--break-system-packages if
# your WSL Python is externally managed), verilator on PATH.

SIM ?= verilator
TOPLEVEL_LANG ?= verilog

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)

VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/processing_element.v
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/pe_row.v
VERILOG_SOURCES += $(PROJECT_ROOT)/rtl/systolic_array.v

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P systolic_array.NUM_PE=2 -P systolic_array.NUM_ROWS=2
else
COMPILE_ARGS += -GNUM_PE=2 -GNUM_ROWS=2
endif

TOPLEVEL = systolic_array
MODULE = test_systolic_array

include $(shell cocotb-config --makefiles)/Makefile.sim
