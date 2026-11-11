`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_nvram.v (iverilog, sim/run_nvram.sh): vic20_nvram (QUIET 2000 clocks) with a model of img_sdc
 (one request at a time: busy, the bytes, done; read bytes as strobes, write bytes taken 2 clocks
 after the address) on a 8K "file".

 1. mount of an 8K file: its 16 sectors in the RAM (port A reads), have = 1
 2. writes of the machine to $0400 (sector 2) and $1805 (sector 12), then quiet: exactly these two
    sectors written back, the file has the new bytes
 3. a write while the RAM is quiet but not yet saved, again after QUIET: one more sector
 4. mount of nothing (size 0): have = 0, a write saves nothing
*/

module tb_nvram;

reg clk = 1'b0;
always #14 clk = !clk;

reg [12:0] m_addr = 13'd0;
reg m_we = 1'b0;
reg [7:0] m_din = 8'd0;
wire [7:0] m_dout;

reg mounted = 1'b0;
reg [31:0] size = 32'd0;
wire rd, wr, have;
wire [3:0] sector;
reg busy = 1'b0, done = 1'b0, strobe = 1'b0;
reg [2:0] slot = 3'd0;
reg [8:0] baddr = 9'd0;
reg [7:0] bdata = 8'd0;
wire [7:0] bout;

vic20_nvram #(.SLOT(3'd7), .QUIET(25'd2000)) nv (
	.clk(clk),
	.m_addr(m_addr), .m_we(m_we), .m_din(m_din), .m_dout(m_dout),
	.mounted(mounted), .size(size), .rd(rd), .wr(wr), .sector(sector),
	.busy(busy), .done(done), .slot(slot), .byte_in_strobe(strobe), .byte_addr(baddr),
	.byte_in_data(bdata), .byte_out_data(bout), .have(have)
);

reg [7:0] file [0:8191];
integer i, k, errors = 0, reads = 0, writes = 0;
reg [3:0] sec;
reg w;
initial for (i = 0; i < 8192; i = i + 1) file[i] = (i * 13 + 5) & 8'hFF;

// the img_sdc model
always begin
	@(posedge clk);
	if (rd || wr) begin
		sec = sector;
		w = wr;
		busy <= 1'b1; slot <= 3'd7;
		repeat (20) @(posedge clk);
		if (!w) begin
			reads = reads + 1;
			for (k = 0; k < 512; k = k + 1) begin
				baddr <= k; bdata <= file[{ sec, k[8:0] }]; strobe <= 1'b1;
				@(posedge clk) strobe <= 1'b0;
				@(posedge clk);
			end
		end
		else begin
			writes = writes + 1;
			for (k = 0; k < 512; k = k + 1) begin
				baddr <= k;
				@(posedge clk); @(posedge clk);
				@(negedge clk) file[{ sec, k[8:0] }] = bout;
			end
		end
		repeat (5) @(posedge clk);
		busy <= 1'b0; done <= 1'b1;
		@(posedge clk) done <= 1'b0;
	end
end

task check;
	input cond;
	input [8*56-1:0] what;
	begin
		if (cond !== 1'b1) begin
			$display("ERROR: %0s", what);
			errors = errors + 1;
		end
	end
endtask

task mwrite;
	input [12:0] a;
	input [7:0] d;
	begin
		@(negedge clk) begin m_addr = a; m_din = d; m_we = 1'b1; end
		repeat (6) @(negedge clk);   // held for a while, as the p2 of the 6502
		m_we = 1'b0;
	end
endtask

reg ok;
initial begin
	repeat (10) @(posedge clk);

	// 1. mount 8K
	@(negedge clk) begin mounted = 1'b1; size = 32'd8192; end
	@(negedge clk) mounted = 1'b0;
	repeat (40000) @(posedge clk);
	check(have, "have after an 8K mount");
	check(reads == 16, "16 sector reads");
	ok = 1'b1;
	for (i = 0; i < 8192; i = i + 37) begin
		@(negedge clk) m_addr = i;
		@(negedge clk);
		if (m_dout !== ((i * 13 + 5) & 8'hFF)) ok = 1'b0;
	end
	check(ok, "the file in the RAM");
	check(writes == 0, "no write after a mount");

	// 2. two writes, then quiet
	mwrite(13'h0400, 8'hA5);
	mwrite(13'h1805, 8'h3C);
	repeat (1000) @(posedge clk);
	check(writes == 0, "no write before QUIET");
	repeat (8000) @(posedge clk);
	check(writes == 2, "two sectors written back");
	check(file[13'h0400] === 8'hA5 && file[13'h1805] === 8'h3C, "the new bytes in the file");
	check(file[13'h0401] === ((13'h0401 * 13 + 5) & 8'hFF), "the other bytes kept");

	// 3. one more write
	mwrite(13'h0010, 8'h77);
	repeat (6000) @(posedge clk);
	check(writes == 3 && file[13'h0010] === 8'h77, "a later write saved");

	// 4. no file
	@(negedge clk) begin mounted = 1'b1; size = 32'd0; end
	@(negedge clk) mounted = 1'b0;
	repeat (10) @(posedge clk);
	check(!have, "have = 0 without a file");
	mwrite(13'h0020, 8'h11);
	repeat (6000) @(posedge clk);
	check(writes == 3, "no write without a file");
	@(negedge clk) m_addr = 13'h0020;
	@(negedge clk);
	check(m_dout === 8'h11, "the RAM still works without a file");

	$display("tb_nvram: %0d errors", errors);
	$finish;
end

endmodule
