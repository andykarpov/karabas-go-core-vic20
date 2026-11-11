`timescale 1ns / 1ps
`default_nettype wire

/*
 vic20_nvram.v

 The 8K NVRAM of the Mega-Cart (megacart.v: mc_nvram_sel, $0400-$0FFF and $9800-$9FFF of the
 VIC, address bits 12..0) in block RAM, kept in a file of the SD card: the F item MC NVRAM (an
 image of the firmware mounter, img_sdc index SLOT), 8192 bytes or more = 16 sectors.
 - mount of a file of 8K or more: its 16 sectors are read into the RAM (the earlier content goes);
   a smaller file or none: the NVRAM lives only until power off, as before;
 - a write of the machine marks its sector (512 bytes) dirty; when no write came for QUIET clocks,
   the dirty sectors are written to the file one after the other (a sector written again while it
   is saved is saved again). A write protected file answers an error: the sector is dropped.
 - img_sdc: the request held until sdc_busy with our index, the end sdc_done with it; read bytes
   as strobes with sdc_byte_addr, write bytes taken OUT_LATENCY 2 clocks after sdc_byte_addr
   (one clock of the RAM).
*/

module vic20_nvram #(
	parameter [2:0] SLOT = 3'd7,
	parameter [24:0] QUIET = 25'd17000000   // ~0.5 s at 35 MHz
) (
	input wire clk,

	// the machine (port A)
	input wire [12:0] m_addr,
	input wire m_we,
	input wire [7:0] m_din,
	output wire [7:0] m_dout,

	// img_sdc
	input wire mounted,           // sdc_img_mounted[SLOT] (a pulse)
	input wire [31:0] size,       // sdc_img_size with it
	output reg rd = 1'b0,
	output reg wr = 1'b0,
	output reg [3:0] sector = 4'd0,
	input wire busy,
	input wire done,
	input wire [2:0] slot,
	input wire byte_in_strobe,
	input wire [8:0] byte_addr,
	input wire [7:0] byte_in_data,
	output wire [7:0] byte_out_data,

	output reg have = 1'b0        // a file is mounted
);

wire me = slot == SLOT;

localparam S_IDLE = 3'd0, S_LOAD_REQ = 3'd1, S_LOAD_WAIT = 3'd2, S_SAVE_REQ = 3'd3, S_SAVE_WAIT = 3'd4;
reg [2:0] state = S_IDLE;
reg [15:0] dirty = 16'd0;
reg [24:0] quiet = 25'd0;
reg mount_pend = 1'b0;       // a mount that came during a request: taken at its end
reg [31:0] mount_size = 32'd0;

kg_tdpram #(.DW(8), .AW(13)) ram (
	.clka(clk), .ena(1'b1), .wea(m_we), .addra(m_addr), .dina(m_din), .douta(m_dout),
	.clkb(clk), .enb(1'b1), .web(byte_in_strobe && me && state == S_LOAD_WAIT),
	.addrb({ sector, byte_addr }), .dinb(byte_in_data), .doutb(byte_out_data)
);

// the lowest dirty sector
function [3:0] first;
	input [15:0] d;
	integer i;
	begin
		first = 4'd0;
		for (i = 15; i >= 0; i = i - 1)
			if (d[i])
				first = i;
	end
endfunction

reg [15:0] clr;
always @(posedge clk) begin
	clr = 16'd0;

	if (m_we)
		quiet <= QUIET;
	else if (quiet != 25'd0)
		quiet <= quiet - 25'd1;

	if (mounted) begin
		mount_pend <= 1'b1;
		mount_size <= size;
	end

	case (state)
	S_IDLE:
		if (mount_pend && !mounted) begin
			mount_pend <= 1'b0;
			have <= mount_size >= 32'd8192;
			clr = 16'hFFFF;
			if (mount_size >= 32'd8192) begin
				sector <= 4'd0;
				rd <= 1'b1;
				state <= S_LOAD_REQ;
			end
		end
		else if (have && dirty != 16'd0 && quiet == 25'd0) begin
			sector <= first(dirty);
			clr = 16'd1 << first(dirty);
			wr <= 1'b1;
			state <= S_SAVE_REQ;
		end

	S_LOAD_REQ:
		if (busy && me) begin
			rd <= 1'b0;
			state <= S_LOAD_WAIT;
		end

	S_LOAD_WAIT:
		if (done && me) begin
			if (sector == 4'd15)
				state <= S_IDLE;
			else begin
				sector <= sector + 4'd1;
				rd <= 1'b1;
				state <= S_LOAD_REQ;
			end
		end

	S_SAVE_REQ:
		if (busy && me) begin
			wr <= 1'b0;
			state <= S_SAVE_WAIT;
		end

	S_SAVE_WAIT:
		if (done && me)
			state <= S_IDLE;

	default:
		state <= S_IDLE;
	endcase

	dirty <= (dirty & ~clr) | (m_we ? (16'd1 << m_addr[12:9]) : 16'd0);
end

endmodule
