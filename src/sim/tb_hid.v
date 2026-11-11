`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_hid.v (iverilog, sim/run_hid.sh): vic20_hid with the keymap of VIC20Nano. A report goes in,
 the matrix is read back row by row as the Kernal scans it (one row low on matrix_out):
 'A' (04) = row 2 column 1; right shift (modifier bit 5) = row 4 column 6; cursor left (50) =
 the cursor key row 2 column 7 + left shift row 3 column 1; F11 = RESTORE; a keypad 5 = '5';
 no key = all high; joystick up + fire of JOY_R.
*/

module tb_hid;

reg clk = 1'b0;
always #14 clk = !clk;

reg [7:0] st = 8'd0, d0 = 8'd0, d1 = 8'd0;
reg [12:0] jl = 13'd0, jr = 13'd0;
reg [7:0] mo = 8'hFF;
wire [7:0] mi;
wire restore_n, fire_n;
wire [3:0] joy_n;

vic20_hid dut (
	.clk(clk), .reset(1'b0),
	.kb_status(st), .kb_dat0(d0), .kb_dat1(d1), .kb_dat2(8'd0), .kb_dat3(8'd0), .kb_dat4(8'd0), .kb_dat5(8'd0),
	.joy_l(jl), .joy_r(jr),
	.matrix_out(mo), .matrix_in(mi), .restore_n(restore_n), .joy_n(joy_n), .fire_n(fire_n)
);

integer errors = 0, r;
reg [63:0] m;

// the whole matrix: row r selected alone
task read_matrix;
	begin
		repeat (40) @(posedge clk);
		for (r = 0; r < 8; r = r + 1) begin
			mo = ~(8'd1 << r);
			#1 m[r*8 +: 8] = mi;
		end
		mo = 8'hFF;
	end
endtask

task expect_keys;
	input [63:0] want;   // 1 = pressed at row * 8 + column
	input [8*40-1:0] what;
	begin
		read_matrix;
		if (m !== ~want) begin
			$display("ERROR: %0s: matrix %h, want %h", what, ~m, want);
			errors = errors + 1;
		end
	end
endtask

initial begin
	expect_keys(64'd0, "no key");
	d0 = 8'h04;                 expect_keys(64'd1 << (2*8+1), "A");
	d0 = 8'h00; st = 8'h20;     expect_keys(64'd1 << (4*8+6), "right shift");
	st = 8'h00; d0 = 8'h50;     expect_keys((64'd1 << (2*8+7)) | (64'd1 << (3*8+1)), "cursor left = shift + cursor right");
	d0 = 8'h5D;                 expect_keys(64'd1 << (0*8+2), "keypad 5");
	d0 = 8'h04; d1 = 8'h17;     expect_keys((64'd1 << (2*8+1)) | (64'd1 << (6*8+2)), "A + T");
	d0 = 8'h44; d1 = 8'h00;     expect_keys(64'd0, "F11: no matrix key");
	if (restore_n !== 1'b0) begin $display("ERROR: F11 is not RESTORE"); errors = errors + 1; end
	d0 = 8'h00;                 expect_keys(64'd0, "release");
	if (restore_n !== 1'b1) begin $display("ERROR: RESTORE stays"); errors = errors + 1; end
	jr = 13'b0000_0100_0010; #1;   // up + A
	if (joy_n !== 4'b1110 || fire_n !== 1'b0) begin $display("ERROR: joystick %b %b", joy_n, fire_n); errors = errors + 1; end
	$display("tb_hid: %0d errors", errors);
	$finish;
end

endmodule
