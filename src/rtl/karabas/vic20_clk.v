`timescale 1ns / 1ps
`default_nettype wire

/*
 vic20_clk.v

 The clocks of the VIC-20 core from the 50 MHz of the board: a chain per video standard, both
 running all the time, and BUFGMUXes that pick one (glitch free: both inputs run) by ntsc.
 A chain: DCM_CLKGEN (the frequency: CLKFX = 50 * M / D, tolerant of input jitter) -> BUFG ->
 PLL (x20 VCO, cleans the jitter of CLKFX for HDMI): clk_sys = VCO / 20, x5 = VCO / 4 at 0 and
 180 degrees (the DDR serial clock of hdmi_tx and its inverse).

   PAL  (6561): 50 * 61 / 86 = 35.465 MHz (8 x 4.43361875 = 35.469: -0.01 %), VCO 709.3 MHz
   NTSC (6560): 50 * 36 / 55 = 32.727 MHz (8 x 4.0909 = 32.727 exactly),       VCO 654.5 MHz

 clk_sys is 8 clocks per pixel of the VIC (upstream 35.775 / 32.94). A PLL alone gives only
 35.0 MHz for PAL from 50 MHz (VCO <= 1000 MHz on the -2 part, PFD >= 19 MHz). Each PLL is held
 in reset until its DCM locks.

 ntsc may come from a register on clk_sys (an OSD switch): BUFGMUX switches at the next edges
 of the clocks without a glitch. locked: both chains.
*/

module vic20_clk (
	input wire clk_50,
	input wire ntsc,
	output wire clk_sys,
	output wire clk_x5,
	output wire clk_x5_n,
	output wire locked
);

// the 50 MHz on a BUFG: the DCMs of both chains take it, wherever map puts them
wire clk_50_ibufg, clk_50_bufg;
IBUFG ibufg_50 (.I(clk_50), .O(clk_50_ibufg));
BUFG bufg_50 (.I(clk_50_ibufg), .O(clk_50_bufg));

wire [5:0] pal_clk, ntsc_clk;
wire pal_locked, ntsc_locked;
wire pal_fx, ntsc_fx, pal_fx_buf, ntsc_fx_buf, pal_dcm_locked, ntsc_dcm_locked;

DCM_CLKGEN #(
	.CLKFX_MULTIPLY(61),
	.CLKFX_DIVIDE(86),
	.CLKFXDV_DIVIDE(2),
	.CLKFX_MD_MAX(0.71),
	.CLKIN_PERIOD(20.0),
	.SPREAD_SPECTRUM("NONE"),
	.STARTUP_WAIT("FALSE")
) dcm_pal (
	.CLKIN(clk_50_bufg),
	.RST(1'b0),
	.FREEZEDCM(1'b0),
	.PROGCLK(1'b0),
	.PROGDATA(1'b0),
	.PROGEN(1'b0),
	.CLKFX(pal_fx),
	.CLKFX180(),
	.CLKFXDV(),
	.LOCKED(pal_dcm_locked),
	.PROGDONE(),
	.STATUS()
);

DCM_CLKGEN #(
	.CLKFX_MULTIPLY(36),
	.CLKFX_DIVIDE(55),
	.CLKFXDV_DIVIDE(2),
	.CLKFX_MD_MAX(0.66),
	.CLKIN_PERIOD(20.0),
	.SPREAD_SPECTRUM("NONE"),
	.STARTUP_WAIT("FALSE")
) dcm_ntsc (
	.CLKIN(clk_50_bufg),
	.RST(1'b0),
	.FREEZEDCM(1'b0),
	.PROGCLK(1'b0),
	.PROGDATA(1'b0),
	.PROGEN(1'b0),
	.CLKFX(ntsc_fx),
	.CLKFX180(),
	.CLKFXDV(),
	.LOCKED(ntsc_dcm_locked),
	.PROGDONE(),
	.STATUS()
);

BUFG bufg_pal_fx (.I(pal_fx), .O(pal_fx_buf));
BUFG bufg_ntsc_fx (.I(ntsc_fx), .O(ntsc_fx_buf));

// the raw PLL outputs (BUFG_MASK 0): the BUFGMUXes are their clock buffers
kg_pll #(
	.CLKIN_PERIOD(28.197),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(20),
	.CLKOUT0_DIVIDE(20),
	.CLKOUT1_DIVIDE(4),
	.CLKOUT2_DIVIDE(4),
	.CLKOUT2_PHASE(180.0),
	.IBUFG(0),
	.BUFG_MASK(6'b000000)
) pll_pal (
	.clk_in(pal_fx_buf),
	.rst(!pal_dcm_locked),
	.clk_out(pal_clk),
	.locked(pal_locked)
);

kg_pll #(
	.CLKIN_PERIOD(30.556),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(20),
	.CLKOUT0_DIVIDE(20),
	.CLKOUT1_DIVIDE(4),
	.CLKOUT2_DIVIDE(4),
	.CLKOUT2_PHASE(180.0),
	.IBUFG(0),
	.BUFG_MASK(6'b000000)
) pll_ntsc (
	.clk_in(ntsc_fx_buf),
	.rst(!ntsc_dcm_locked),
	.clk_out(ntsc_clk),
	.locked(ntsc_locked)
);

BUFGMUX mux_sys (.I0(pal_clk[0]), .I1(ntsc_clk[0]), .S(ntsc), .O(clk_sys));
BUFGMUX mux_x5 (.I0(pal_clk[1]), .I1(ntsc_clk[1]), .S(ntsc), .O(clk_x5));
BUFGMUX mux_x5_n (.I0(pal_clk[2]), .I1(ntsc_clk[2]), .S(ntsc), .O(clk_x5_n));

assign locked = pal_locked && ntsc_locked;

endmodule
