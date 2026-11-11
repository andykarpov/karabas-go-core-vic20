# Command line build of the Commodore VIC-20 core (ISE 14.7), as core-atarist / core-archie.
#
#   make vic20-xst       the machine alone (vic20.prj: vic20_core = VIC-20 + C1541 + C1530,
#                        -iobuf NO): the fit check of docs/PLAN.md Ф0
#   make vic20-report    its utilization and speed from the .syr
#   make clean           the intermediate files
#
# The board targets (make go|mini|minig, <board>-xst / -impl / -core / -report) come with the
# board tops in Ф2 / Ф5.

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
PART = xc6slx25-ftg256-2

SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
.NOTPARALLEL:
# settings64.sh takes the arguments of the shell that sources it: none here
XIL = source $(ISE_SETTINGS) > /dev/null;

# read by the sources ($readmemh), not in the prj
INCLUDES = $(wildcard rom/*.hex)

.PHONY: clean vic20-xst vic20-report

prj_src = $(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' $(1) 2>/dev/null)

vic20.ngc: vic20.prj vic20.xst $(call prj_src,vic20.prj) $(INCLUDES)
	mkdir -p xst/projnav.tmp
	$(XIL) xst -intstyle ise -ifn vic20.xst -ofn vic20.syr

vic20-xst: vic20.ngc
vic20-report:
	@sed -n '/Device utilization summary/,/Partition Resource Summary/p' vic20.syr | grep -E "Number of (Slice Registers|Slice LUTs|Block RAM/FIFO|DSP48)"
	@grep -E "Minimum period|Xst:737" vic20.syr | sort -u | head

clean:
	rm -rf xst _ngo _xmsgs xlnx_auto_0_xdb iseconfig
	rm -f vic20.ngc vic20.ngr vic20.syr vic20.lso vic20_xst.xrpt
