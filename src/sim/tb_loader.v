`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_loader.v (iverilog, sim/run_loader.sh): vic20_loader + vic20_sram on a model of the board SRAM
 (2M x 16, asynchronous, read after 10 ns).

 1. a PRG at $1001 that runs into $2000 (8K expansion): bytes below $2000 as conf writes, the
    others in the SRAM; then the pointers $2D..$32, $AE/$AF = the end address
 2. a cartridge at $A000 (8K + 2): all in the SRAM, cart_blk = $A000, hold_reset while it loads;
    eject clears cart_blk
 2b. a cartridge of two files ($2000, $A000): the blocks add up; a file on a taken block: a new
     cartridge (the old blocks go)
 2c. a PRG after it: no hold_reset while the slot of the cartridge is still on file_slot
 3. a Kernal (8K, no header): conf writes at $E000..$FFFF
 3b. a 32K DOS image (slot 6): dos_* writes, its last 16K stay; disk_hold while it loads
 3c. a Mega-Cart (slot 5, 4K of it here): mc_loaded, hold_reset, laddr from $200000, a
     cartridge after it clears mc_loaded
 4. the machine side of vic20_sram: a write (cwe for 16 clocks), then a read of it and of a
    loader byte (cdata within 7 clocks)
*/

module tb_loader;

reg clk = 1'b0;
always #14 clk = !clk;   // 35.7 MHz

reg file_active = 1'b0, file_wr = 1'b0, eject = 1'b0, file_reset = 1'b0;
reg [7:0] file_slot = 8'd0, file_data = 8'd0;
reg [31:0] file_addr = 32'd0;

wire conf_wr, lwe, hold_reset;
wire [15:0] conf_ai;
wire [21:0] laddr;
wire [7:0] conf_di, lwdata;
wire [4:0] cart_blk;
wire mc_loaded, dos_wr, disk_hold;
wire [13:0] dos_addr;
wire [7:0] dos_data;
reg [7:0] dos [0:16383];
reg mega_addr_ok = 1'b1, mega_seen = 1'b0;
always @(posedge clk) begin
	if (dos_wr) dos[dos_addr] <= dos_data;
	if (lwe && file_slot == 8'd5) begin
		mega_seen <= 1'b1;
		if (laddr !== 22'h200000 + file_addr[21:0]) mega_addr_ok <= 1'b0;
	end
end

vic20_loader dut (
	.clk(clk), .reset(1'b0),
	.file_reset(file_reset), .file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data),
	.file_wr(file_wr), .eject(eject),
	.conf_wr(conf_wr), .conf_ai(conf_ai), .conf_di(conf_di),
	.lwe(lwe), .laddr(laddr), .lwdata(lwdata),
	.cart_blk(cart_blk), .hold_reset(hold_reset),
	.mc_loaded(mc_loaded), .dos_wr(dos_wr), .dos_addr(dos_addr), .dos_data(dos_data), .disk_hold(disk_hold)
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
	.caddr({ 6'd0, caddr }), .cdata(cdata), .cwe(cwe), .cwdata(cwdata),
	.treq(1'b0), .taddr(22'd0), .tdata(), .tack(),
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
		// as the firmware (core_ioctl_send): IOCTL_STATE 1, then IOCTL_SLOT (file_reset + slot)
		@(negedge clk) file_active = 1'b1;
		repeat (4) @(posedge clk);
		@(negedge clk) begin file_slot = slot; file_reset = 1'b1; end
		@(negedge clk) file_reset = 1'b0;
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
reg ok, saw_hold;
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

	// 2b. a cartridge of two files: $2000 then $A000 add up; $A000 again is a new cartridge
	send_file(8'd2, 16'h2000, 1'b1, 16'h0020);
	send_file(8'd2, 16'hA000, 1'b1, 16'h0020);
	check(cart_blk == 5'b10010, "two cartridge files: $2000 + $A000");
	send_file(8'd2, 16'hA000, 1'b1, 16'h0020);
	check(cart_blk == 5'b10000, "a taken block: a new cartridge");

	// 2c. a PRG after the cartridge: while its slot is not yet sent, file_slot is the cartridge's
	// (the firmware order): hold_reset must stay low (26111109 reset the machine, the PRG lost)
	saw_hold = 1'b0;
	fork
		send_file(8'd1, 16'h1001, 1'b1, 16'h0010);
		begin : watch
			repeat (2000) begin @(posedge clk); if (hold_reset) saw_hold = 1'b1; end
		end
	join
	check(!saw_hold, "no hold_reset for a PRG after a cartridge");
	check(conf_seen[16'h1001], "the PRG after a cartridge is written");

	// 3. Kernal, 8K without a header
	send_file(8'd4, 16'h0000, 1'b0, 16'h2000);
	ok = 1'b1;
	for (i = 0; i < 16'h2000; i = i + 1)
		if (!conf_seen[16'hE000 + i] || conf[16'hE000 + i] !== ((i * 7) & 8'hFF)) ok = 1'b0;
	check(ok, "Kernal at $E000 (conf)");

	// 3b. DOS, 32K
	fork
		send_file(8'd6, 16'h0000, 1'b0, 16'h8000);
		begin repeat (8) @(posedge clk); check(disk_hold, "disk_hold while a DOS loads"); end
	join
	ok = 1'b1;
	for (i = 0; i < 16'h4000; i = i + 1)
		if (dos[i] !== (((i + 16'h4000) * 7) & 8'hFF)) ok = 1'b0;
	check(ok, "DOS: the last 16K of a 32K image");

	// 3c. Mega-Cart (4K of it)
	fork
		send_file(8'd5, 16'h0000, 1'b0, 16'h1000);
		begin repeat (8) @(posedge clk); check(hold_reset && mc_loaded, "hold_reset + mc_loaded while a Mega-Cart loads"); end
	join
	check(mc_loaded && mega_seen && mega_addr_ok, "Mega-Cart bytes at $200000 + offset");
	send_file(8'd2, 16'hA000, 1'b1, 16'h0010);
	check(!mc_loaded, "a cartridge takes the Mega-Cart out");

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
