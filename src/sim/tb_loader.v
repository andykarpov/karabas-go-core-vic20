`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_loader.v (iverilog, sim/run_loader.sh): vic20_loader + vic20_sram on a model of the board SRAM
 (2M x 16, asynchronous, read after 10 ns).

 1. a PRG at $1001 that runs into $2000 (8K expansion): bytes below $2000 as conf writes, the
    others in the SRAM; then the pointers $2D..$32, $AE/$AF = the end address
 2. a cartridge at $A000 (8K + 2): all in the SRAM, cart_blk = $A000, hold_reset while it loads;
    eject clears cart_blk
 3. a Kernal (8K, no header): conf writes at $E000..$FFFF
 4. the machine side of vic20_sram: a write (cwe for 16 clocks), then a read of it and of a
    loader byte (cdata within 7 clocks)
*/

module tb_loader;

reg clk = 1'b0;
always #14 clk = !clk;   // 35.7 MHz

reg file_active = 1'b0, file_wr = 1'b0, eject = 1'b0;
reg [7:0] file_slot = 8'd0, file_data = 8'd0;
reg [31:0] file_addr = 32'd0;

wire conf_wr, lwe, hold_reset;
wire [15:0] conf_ai;
wire [20:0] laddr;
wire [7:0] conf_di, lwdata;
wire [4:0] cart_blk;

vic20_loader dut (
	.clk(clk), .reset(1'b0),
	.file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data),
	.file_wr(file_wr), .eject(eject),
	.conf_wr(conf_wr), .conf_ai(conf_ai), .conf_di(conf_di),
	.lwe(lwe), .laddr(laddr), .lwdata(lwdata),
	.cart_blk(cart_blk), .hold_reset(hold_reset)
);

reg [15:0] caddr = 16'd0;
reg cwe = 1'b0;
reg [7:0] cwdata = 8'd0;
wire [7:0] cdata;
wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N, MRD_N;

vic20_sram sram (
	.clk(clk),
	.caddr({ 5'd0, caddr }), .cdata(cdata), .cwe(cwe), .cwdata(cwdata),
	.treq(1'b0), .taddr(21'd0), .tdata(), .tack(),
	.lwe(lwe), .laddr(laddr), .lwdata(lwdata),
	.MA(MA), .MD(MD), .MWR_N(MWR_N), .MRD_N(MRD_N)
);

// the SRAM chips
reg [7:0] lo [0:65535];
reg [7:0] hi [0:65535];
wire [15:0] ma = MA[15:0];
assign #10 MD = (MRD_N == 2'b00) ? { hi[ma], lo[ma] } : 16'bz;
always @(posedge MWR_N[0]) lo[ma] <= MD[7:0];
always @(posedge MWR_N[1]) hi[ma] <= MD[15:8];
function [7:0] sram_byte;
	input [15:0] a;
	sram_byte = a[0] ? hi[a[15:1]] : lo[a[15:1]];
endfunction

// what the conf bus wrote
reg [7:0] conf [0:65535];
reg conf_seen [0:65535];
integer i, errors = 0;
initial for (i = 0; i < 65536; i = i + 1) begin conf_seen[i] = 1'b0; lo[i] = 8'hFF; hi[i] = 8'hFF; end
always @(posedge clk)
	if (conf_wr) begin
		conf[conf_ai] <= conf_di;
		conf_seen[conf_ai] <= 1'b1;
	end

task send_file;
	input [7:0] slot;
	input [15:0] load;      // the load address (header), or none with hdr = 0
	input hdr;
	input integer len;      // bytes after the header
	integer k;
	begin
		file_slot = slot;
		file_active = 1'b1;
		repeat (4) @(posedge clk);
		for (k = 0; k < len + (hdr ? 2 : 0); k = k + 1) begin
			file_addr = k;
			file_data = !hdr ? (k * 7) : k == 0 ? load[7:0] : k == 1 ? load[15:8] : ((k - 2) * 7);
			@(negedge clk) file_wr = 1'b1;
			@(negedge clk) file_wr = 1'b0;
			repeat (34) @(posedge clk);   // a byte per microsecond
		end
		@(negedge clk) file_active = 1'b0;
		repeat (40) @(posedge clk);
	end
endtask

task check;
	input cond;
	input [8*48-1:0] what;
	begin
		if (cond !== 1'b1) begin
			$display("ERROR: %0s", what);
			errors = errors + 1;
		end
	end
endtask

reg [15:0] a;
reg ok;
initial begin
	repeat (10) @(posedge clk);

	// 1. PRG $1001..$2100 (0x1100 bytes)
	send_file(8'd1, 16'h1001, 1'b1, 16'h1100);
	ok = 1'b1;
	for (i = 0; i < 16'h1100; i = i + 1) begin
		a = 16'h1001 + i;
		if (a < 16'h2000) begin
			if (!conf_seen[a] || conf[a] !== ((i * 7) & 8'hFF)) ok = 1'b0;
		end
		else if (conf_seen[a] || sram_byte(a) !== ((i * 7) & 8'hFF)) ok = 1'b0;
	end
	check(ok, "PRG bytes: conf below $2000, SRAM above");
	check(conf[16'h2D] === 8'h01 && conf[16'h2E] === 8'h21 && conf[16'h2F] === 8'h01 && conf[16'h30] === 8'h21 &&
	      conf[16'h31] === 8'h01 && conf[16'h32] === 8'h21 && conf[16'hAE] === 8'h01 && conf[16'hAF] === 8'h21,
	      "PRG pointers = $2101");
	check(cart_blk === 5'd0, "PRG sets no cartridge block");

	// 2. cartridge at $A000
	fork
		send_file(8'd2, 16'hA000, 1'b1, 16'h2000);
		begin repeat (8) @(posedge clk); check(hold_reset, "hold_reset while a cartridge loads"); end
	join
	check(!hold_reset, "hold_reset after the cartridge");
	check(cart_blk == 5'b10000, "cartridge block $A000");
	ok = 1'b1;
	for (i = 0; i < 16'h2000; i = i + 1)
		if (sram_byte(16'hA000 + i) !== ((i * 7) & 8'hFF) || conf_seen[16'hA000 + i]) ok = 1'b0;
	check(ok, "cartridge bytes in the SRAM only");
	@(negedge clk) eject = 1'b1;
	@(negedge clk) eject = 1'b0;
	@(posedge clk);
	check(cart_blk == 5'd0, "eject clears the blocks");

	// 3. Kernal, 8K without a header
	send_file(8'd4, 16'h0000, 1'b0, 16'h2000);
	ok = 1'b1;
	for (i = 0; i < 16'h2000; i = i + 1)
		if (!conf_seen[16'hE000 + i] || conf[16'hE000 + i] !== ((i * 7) & 8'hFF)) ok = 1'b0;
	check(ok, "Kernal at $E000 (conf)");

	// 4. the machine: write $4123, read it back and a loader byte
	@(negedge clk) begin caddr = 16'h4123; cwdata = 8'h5A; cwe = 1'b1; end
	repeat (16) @(posedge clk);
	@(negedge clk) cwe = 1'b0;
	repeat (8) @(posedge clk);
	check(cdata === 8'h5A, "machine write / read $4123");
	@(negedge clk) caddr = 16'hA001;
	repeat (7) @(posedge clk);
	#1 check(cdata === 8'd7, "read of a loader byte $A001 within 7 clocks");
	@(negedge clk) caddr = 16'h4124;
	repeat (7) @(posedge clk);
	#1 check(cdata === 8'hFF, "a neighbour byte unchanged");

	$display("tb_loader: %0d errors", errors);
	$finish;
end

endmodule
