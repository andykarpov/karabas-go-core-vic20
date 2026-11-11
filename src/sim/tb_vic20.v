`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_vic20.v

 vic20_core (the ghdl netlist of the VHDL plus the Verilog modules) with a model of the memory
 behind extmem_*: 64K, read data registered on clk_sys (as a block RAM or the SRAM controller of
 the board will give them), written while extmem_sel and !extmem_r_wn (the whole p2 phase: the
 same byte again and again). A block of ram_ext_ro is not written (vic20.vhd itself protects only
 $A000). The keyboard matrix, the SD card, conf writes and the frame capture are in sim_vic20.cpp.
*/

module tb_vic20 (
	input wire clk_sys,
	input wire reset,
	input wire pal,

	input wire [4:0] ram_ext,
	input wire [4:0] ram_ext_ro,

	output wire [7:0] kbd_matrix_out,
	input wire [7:0] kbd_matrix_in,
	input wire [3:0] joy_n,
	input wire fire_n,

	input wire conf_wr,
	input wire [15:0] conf_ai,
	input wire [7:0] conf_di,

	input wire disk_reset,
	input wire disk_change,
	input wire disk_mount,
	input wire disk_readonly,
	output wire disk_led,
	output wire [31:0] sd_lba,
	output wire sd_rd,
	output wire sd_wr,
	input wire sd_ack,
	input wire [8:0] sd_buff_addr,
	input wire [7:0] sd_buff_dout,
	output wire [7:0] sd_buff_din,
	input wire sd_buff_wr,

	output wire ce_pix,
	output wire [3:0] video_r,
	output wire [3:0] video_g,
	output wire [3:0] video_b,
	output wire hsync,
	output wire vsync,
	output wire hblank,
	output wire vblank,
	output wire [5:0] audio,

	// the scandoubler of the board tops on the picture (the geometry of the HDMI frame)
	output wire sd_hs_n,
	output wire sd_vs_n,
	output wire sd_hb,
	output wire sd_vb,       // the vertical blank of the tops: vblank of the VIC at each doubled line

	// the external memory bus, for the harness (dumps, checks)
	output wire extmem_sel,
	output wire extmem_r_wn,
	output wire [15:0] extmem_addr,
	output wire [7:0] extmem_dout
);

	reg [7:0] mem [0:65535];
	integer i;
	initial
		for (i = 0; i < 65536; i = i + 1)
			mem[i] = 8'hFF;

	// the block of an address: 0 = $0400-$0FFF, 1..3 = $2000 / $4000 / $6000, 4 = $A000
	wire [2:0] blk = extmem_addr[15:13];
	wire ro = (blk == 3'd0) ? ram_ext_ro[0] :
	          (blk == 3'd5) ? ram_ext_ro[4] :
	          (blk >= 3'd1 && blk <= 3'd3) ? ram_ext_ro[blk] : 1'b0;

	reg [7:0] extmem_din = 8'hFF;
	always @(posedge clk_sys) begin
		extmem_din <= mem[extmem_addr];
		if (extmem_sel && !extmem_r_wn && !ro)
			mem[extmem_addr] <= extmem_dout;
	end

	vic20_core machine (
		.clk_sys(clk_sys),
		.reset(reset),
		.pal(pal),
		.center(2'b00),
		.wide(1'b0),

		.ce_pix(ce_pix),
		.video_r(video_r),
		.video_g(video_g),
		.video_b(video_b),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),
		.audio(audio),

		.kbd_matrix_out(kbd_matrix_out),
		.kbd_matrix_in(kbd_matrix_in),
		.restore_n(1'b1),

		.joy_n(joy_n),
		.fire_n(fire_n),
		.potx(8'hFF),
		.poty(8'hFF),

		.ram_ext_ro(ram_ext_ro),
		.ram_ext(ram_ext),
		.extmem_sel(extmem_sel),
		.extmem_r_wn(extmem_r_wn),
		.extmem_addr(extmem_addr),
		.extmem_din(extmem_din),
		.extmem_dout(extmem_dout),
		.io2_sel(),
		.io3_sel(),
		.blk123_sel(),
		.blk5_sel(),
		.ram123_sel(),
		.p2h(),

		.conf_wr(conf_wr),
		.conf_ai(conf_ai),
		.conf_di(conf_di),

		.disk_reset(disk_reset),
		.disk_pause(1'b0),
		.disk_change(disk_change),
		.disk_mount(disk_mount),
		.disk_readonly(disk_readonly),
		.disk_g64(1'b0),
		.disk_led(disk_led),
		.dos_wr(1'b0),
		.dos_addr(14'd0),
		.dos_data(8'd0),
		.sd_lba(sd_lba),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_ack(sd_ack),
		.sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout),
		.sd_buff_din(sd_buff_din),
		.sd_buff_wr(sd_buff_wr),

		.tap_restart(reset),
		.tap_version(2'd1),
		.tap_data(8'd0),
		.tap_wrreq(1'b0),
		.tap_wrfull(),
		.tap_error(),
		.tap_play_stop(1'b0),
		.cass_motor(),
		.cass_sense(),
		.cass_read(),
		.cass_run(),

		.user_port_in(8'hFF),
		.user_port_out(),
		.user_cb1_in(1'b1),
		.user_cb1_out(),
		.user_cb2_in(1'b1),
		.user_cb2_out()
	);

	scandoubler #(.HCNT_WIDTH(10)) doubler (
		.clk_sys(clk_sys),
		.bypass(1'b0),
		.ce_divider(3'd1),
		.pixel_ena(),
		.scanlines(2'b00),
		.hb_in(hblank),
		.vb_in(vblank),
		.hs_in(hsync),
		.vs_in(vsync),
		.r_in(video_r),
		.g_in(video_g),
		.b_in(video_b),
		.hb_out(sd_hb),
		.vb_out(),
		.hs_out(sd_hs_n),
		.vs_out(sd_vs_n),
		.r_out(),
		.g_out(),
		.b_out()
	);

	// as the tops: the vblank of the VIC taken at the start of each doubled line (vb_out of the
	// scandoubler is lost: its 10-bit sample counter wraps in the 1136 samples of a line)
	reg sd_hs_d = 1'b1, vb_line = 1'b1;
	always @(posedge clk_sys) begin
		sd_hs_d <= sd_hs_n;
		if (sd_hs_d && !sd_hs_n)
			vb_line <= vblank;
	end
	assign sd_vb = vb_line;

endmodule
