`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_tape.v (iverilog, sim/run_tape.sh): vic20_loader + vic20_tape + vic20_sram on a model of the
 SRAM. A 1500-byte .tap (version byte 12 = 2) goes in through the loader (slot 3); then:
 the version, one PLAY pulse after the file, the bytes into a model of the c1530 FIFO (512
 deep, a reader takes one byte every 40 clocks) in the order of the file, no byte twice, none
 lost; tap_error (the FIFO empty) restarts the tape from byte 0. The machine keeps reading the
 SRAM meanwhile (its data unchanged).
 The PLAY key of c1530 is a toggle (modelled: sense, reset to STOP by tap_restart): the file is
 loaded with file_active dropping once in the middle (as a firmware may do), and the tape must
 still end at PLAY. A PRG after the tape (its slot sent after file_active) leaves the tape as it is.
*/

module tb_tape;

reg clk = 1'b0;
always #14 clk = !clk;

reg file_active = 1'b0, file_wr = 1'b0, tap_error = 1'b0, play_key = 1'b0, file_reset = 1'b0;
reg [7:0] file_slot = 8'd0, file_data = 8'd0;
reg [31:0] file_addr = 32'd0;

wire conf_wr, lwe, hold_reset;
wire [15:0] conf_ai;
wire [21:0] laddr, taddr;
wire [7:0] conf_di, lwdata, tdata;
wire [4:0] cart_blk;
wire treq, tack, file_on;

vic20_loader loader (
	.clk(clk), .reset(1'b0),
	.file_reset(file_reset), .file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data),
	.file_wr(file_wr), .eject(1'b0), .file_on(file_on),
	.conf_wr(conf_wr), .conf_ai(conf_ai), .conf_di(conf_di),
	.lwe(lwe), .laddr(laddr), .lwdata(lwdata),
	.cart_blk(cart_blk), .hold_reset(hold_reset),
	.mc_loaded(), .dos_wr(), .dos_addr(), .dos_data(), .disk_hold()
);

wire tap_restart, tap_wrreq, tap_play_stop;
wire [1:0] tap_version;
wire [7:0] tap_data;
reg [9:0] fifo_n = 10'd0;
wire tap_wrfull = fifo_n == 10'd512;

vic20_tape tape (
	.clk(clk), .reset(1'b0),
	.file_active(file_on), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data),
	.file_wr(file_wr), .play(play_key),
	.treq(treq), .taddr(taddr), .tdata(tdata), .tack(tack),
	.tap_restart(tap_restart), .tap_version(tap_version), .tap_data(tap_data), .tap_wrreq(tap_wrreq),
	.tap_wrfull(tap_wrfull), .tap_error(tap_error), .cass_run(1'b0), .cass_sense(sense), .tap_play_stop(tap_play_stop)
);
defparam tape.AUTOPLAY = 23'd2000;

// the PLAY / STOP key of c1530: a toggle on the rising edge, STOP while restarted
reg sense = 1'b1, toggle_d = 1'b0;
always @(posedge clk)
	if (tap_restart) begin
		sense <= 1'b1;
		toggle_d <= 1'b0;
	end
	else begin
		toggle_d <= tap_play_stop;
		if (tap_play_stop && !toggle_d)
			sense <= !sense;
	end

wire [7:0] cdata;
wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N, MRD_N;
vic20_sram sram (
	.clk(clk),
	.caddr(22'h001234), .cdata(cdata), .cwe(1'b0), .cwdata(8'd0),
	.treq(treq), .taddr(taddr), .tdata(tdata), .tack(tack),
	.lwe(lwe), .laddr(laddr), .lwdata(lwdata),
	.MA(MA), .MD(MD), .MWR_N(MWR_N), .MRD_N(MRD_N)
);

reg [7:0] lo [0:1048575];
reg [7:0] hi [0:1048575];
wire [19:0] ma = MA[19:0];
assign #10 MD = (MRD_N == 2'b00) ? { hi[ma], lo[ma] } : 16'bz;
always @(posedge MWR_N[0]) lo[ma] <= MD[7:0];
always @(posedge MWR_N[1]) hi[ma] <= MD[15:8];
integer i, errors = 0, got = 0, plays = 0, restarts = 0;
initial for (i = 0; i < 1048576; i = i + 1) begin lo[i] = 8'hFF; hi[i] = 8'hFF; end
initial begin lo[20'h91A] = 8'h3C; end   // byte $1234 of the machine

function [7:0] tap_byte;
	input integer k;
	tap_byte = k == 12 ? 8'd2 : (k * 13 + (k >> 8)) & 8'hFF;
endfunction

// the FIFO of c1530: count, check the order
reg [8:0] rd_div = 9'd0;
always @(posedge clk) begin
	if (tap_restart)
		fifo_n <= 10'd0;
	else begin
		rd_div <= (rd_div == 9'd39) ? 9'd0 : rd_div + 9'd1;
		// c1530 takes bytes only while playing (PLAY pressed)
		fifo_n <= fifo_n + (tap_wrreq ? 10'd1 : 10'd0) - ((rd_div == 9'd0 && fifo_n != 10'd0 && !sense) ? 10'd1 : 10'd0);
	end
	if (tap_restart)
		got = 0;   // the bytes of an interrupted load: the FIFO is emptied
	if (tap_wrreq) begin
		if (tap_wrfull) begin $display("ERROR: a write into a full FIFO"); errors = errors + 1; end
		if (tap_data !== tap_byte(got)) begin
			if (errors < 5) $display("ERROR: tape byte %0d = %h, want %h", got, tap_data, tap_byte(got));
			errors = errors + 1;
		end
		got = got + 1;
	end
	if (cdata !== 8'h3C && $time > 1000) begin $display("ERROR: machine read %h", cdata); errors = errors + 1; end
end

initial begin
	repeat (10) @(posedge clk);
	// as the firmware: IOCTL_STATE 1 with the slot of the previous file, then IOCTL_SLOT
	file_slot = 8'd1;
	@(negedge clk) file_active = 1'b1;
	repeat (4) @(posedge clk);
	@(negedge clk) begin file_slot = 8'd3; file_reset = 1'b1; end
	@(negedge clk) file_reset = 1'b0;
	repeat (4) @(posedge clk);
	for (i = 0; i < 1500; i = i + 1) begin
		if (i == 700) begin   // the load drops for a while
			@(negedge clk) file_active = 1'b0;
			repeat (300) @(posedge clk);
			@(negedge clk) file_active = 1'b1;
			repeat (4) @(posedge clk);
		end
		file_addr = i;
		file_data = tap_byte(i);
		@(negedge clk) file_wr = 1'b1;
		@(negedge clk) file_wr = 1'b0;
		repeat (6) @(posedge clk);
	end
	@(negedge clk) file_active = 1'b0;
	repeat (200000) @(posedge clk);
	if (got !== 1500) begin $display("ERROR: %0d bytes played, want 1500", got); errors = errors + 1; end
	if (sense !== 1'b0) begin $display("ERROR: the tape is at STOP after the load"); errors = errors + 1; end
	if (tap_version !== 2'd2) begin $display("ERROR: version %0d", tap_version); errors = errors + 1; end
	// the end: c1530 reports its FIFO empty -> from the start again, the key released (STOP)
	@(negedge clk) tap_error = 1'b1;
	@(negedge clk) tap_error = 1'b0;
	repeat (20000) @(posedge clk);
	if (got !== 512) begin $display("ERROR: after the end %0d bytes (a full FIFO), want 512", got); errors = errors + 1; end
	if (sense !== 1'b1) begin $display("ERROR: PLAY after the end of the tape"); errors = errors + 1; end
	// Tape play: PLAY again, the rest of the tape follows
	@(negedge clk) play_key = 1'b1;
	@(negedge clk) play_key = 1'b0;
	repeat (200000) @(posedge clk);
	if (got !== 1500 || sense !== 1'b0) begin $display("ERROR: after Tape play %0d bytes, sense %b", got, sense); errors = errors + 1; end
	// a restart of c1530 (a reset of the machine) while the key is down: PLAY again
	@(negedge clk) force tape.restart = 1'b1;
	repeat (4) @(posedge clk);
	@(negedge clk) release tape.restart;
	repeat (10000) @(posedge clk);
	if (sense !== 1'b0) begin $display("ERROR: STOP after a restart with the key down"); errors = errors + 1; end
	// another file after the tape (a PRG: IOCTL_STATE 1 with the tape slot still on, then the slot):
	// the tape keeps its length
	@(negedge clk) file_active = 1'b1;
	repeat (4) @(posedge clk);
	@(negedge clk) begin file_slot = 8'd1; file_reset = 1'b1; end
	@(negedge clk) file_reset = 1'b0;
	for (i = 0; i < 4; i = i + 1) begin
		file_addr = i; file_data = 8'h10;
		@(negedge clk) file_wr = 1'b1;
		@(negedge clk) file_wr = 1'b0;
		repeat (6) @(posedge clk);
	end
	@(negedge clk) file_active = 1'b0;
	repeat (100) @(posedge clk);
	if (tape.last !== 21'd1500) begin $display("ERROR: tape length %0d after a PRG, want 1500", tape.last); errors = errors + 1; end
	$display("tb_tape: %0d errors", errors);
	$finish;
end

endmodule
