`timescale 1ns / 1ps
`default_nettype wire

/*
 vic20_tape.v

 The tape of the VIC-20: a .tap file of the FL item (slot SLOT_TAPE) lies in the SRAM from
 TAPE_BASE (vic20_loader writes it); this plays it into the FIFO of c1530 (vic20_core tap_*), as
 the top of VIC20Nano did from its SDRAM:
 - while the file loads: the player is held (restart), the TAP version is byte 12 of the file;
 - at the end of the file: the length is taken and PLAY is pressed (play_stop toggle pulse:
   upstream autoplay), so LOAD on the VIC starts the tape at once;
 - playing: while the FIFO is not full and bytes are left, one byte after the other is read from
   the SRAM (treq / tack) and written into the FIFO (c1530 skips the 20-byte header itself and
   runs the bytes with the motor of the VIC);
 - the tape starts again from the beginning (restart: the FIFO emptied, the header counted again)
   on a reset of the machine, at a new file, when c1530 found its FIFO empty while playing
   (tap_error: the end), and when the motor runs with less than 80 bytes left (upstream);
 - play (the OSD trigger Tape play): the PLAY / STOP key of the datasette (a toggle pulse).
*/

module vic20_tape #(
	parameter [7:0] SLOT_TAPE = 8'd3,
	parameter [20:0] TAPE_BASE = 21'h100000,
	parameter [20:0] TAPE_MAX = 21'h0FFFFF
) (
	input wire clk,
	input wire reset,            // the machine

	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,
	input wire play,             // the OSD trigger (a level while held)

	output reg treq = 1'b0,
	output wire [20:0] taddr,
	input wire [7:0] tdata,
	input wire tack,

	output reg tap_restart = 1'b1,
	output reg [1:0] tap_version = 2'd0,
	output reg [7:0] tap_data = 8'd0,
	output reg tap_wrreq = 1'b0,
	input wire tap_wrfull,
	input wire tap_error,
	input wire cass_run,
	output reg tap_play_stop = 1'b0
);

wire loading = file_active && file_slot == SLOT_TAPE;
reg loading_d = 1'b0, play_d = 1'b0, autoplay = 1'b0;
reg [20:0] last = 21'd0;     // the length of the file (0: no tape)
reg [20:0] pos = 21'd0;      // the next byte to give c1530
reg [20:0] size = 21'd0;     // the bytes of the file that is loading
reg wait_full = 1'b0;        // a byte was written: the FIFO full flag follows a clock later

assign taddr = TAPE_BASE + pos;

wire near_end = cass_run && (last - pos) < 21'd80;
wire restart = reset || loading || tap_error || near_end;

always @(posedge clk) begin
	loading_d <= loading;
	play_d <= play;
	tap_wrreq <= 1'b0;
	tap_play_stop <= 1'b0;

	if (loading && file_wr) begin
		if (file_addr == 32'd12)
			tap_version <= file_data[1:0];
		if (file_addr <= TAPE_MAX)
			size <= file_addr[20:0] + 21'd1;
	end
	if (loading && !loading_d)
		size <= 21'd0;
	if (!loading && loading_d) begin
		last <= size;
		autoplay <= 1'b1;
	end

	tap_restart <= restart;
	if (restart) begin
		pos <= 21'd0;
		treq <= 1'b0;
		wait_full <= 1'b0;
	end
	else begin
		wait_full <= 1'b0;
		if (treq) begin
			if (tack) begin
				treq <= 1'b0;
				tap_data <= tdata;
				tap_wrreq <= 1'b1;
				wait_full <= 1'b1;
				pos <= pos + 21'd1;
			end
		end
		else if (!tap_wrreq && !wait_full && !tap_wrfull && pos < last)
			treq <= 1'b1;

		// PLAY after a new file (once the restart of its load is over), or from the OSD
		if (autoplay) begin
			autoplay <= 1'b0;
			tap_play_stop <= 1'b1;
		end
	end
	if (play && !play_d)
		tap_play_stop <= 1'b1;
end

endmodule
