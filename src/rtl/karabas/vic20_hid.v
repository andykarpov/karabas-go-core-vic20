`timescale 1ns / 1ps
`default_nettype wire

/*
 vic20_hid.v

 The USB devices of the mcu link (kg_mcu: the keyboard report, two joysticks) as the inputs of
 the VIC-20: its keyboard matrix, the joystick port, RESTORE.

 Keyboard: the report (KB_STATUS = modifiers, KB_DAT0..5 = USB HID usage codes) is scanned
 serially, one item per clock through ONE keymap (vic20_keymap.v of VIC20Nano): items 0..5 the
 key codes, 6..13 the modifier bits as the codes 68..6F of the keymap (as st_hid of core-atarist).
 A key may also need a shift (row_s / column_s of the keymap: cursor left / up, F2 / F4 / F6 /
 F8, Insert: the shifted key of the VIC). A scan builds the matrix (8 rows x 8 columns, 0 =
 pressed) and the matrix is taken at its end, every 14 clocks.
 Matrix: row r = bit r of matrix_out (VIA2 port B, the scan pattern, low = selected), column c =
 bit c of matrix_in (VIA2 port A): matrix_in is the AND of the selected rows, as hid.v of
 VIC20Nano.
 RESTORE: F11 (upstream: the same key), low active (VIA1 CA1).

 Joysticks: kg_mcu JOY: [1] up, [2] down, [3] left, [4] right, [6] A, [7] B. The VIC-20 has one
 port: JOY_L or JOY_R, either works (OR), fire = A or B. joy_n: 0 up, 1 down, 2 left, 3 right,
 low active, as vic20.vhd.
*/

module vic20_hid (
	input wire clk,
	input wire reset,

	input wire [7:0] kb_status,
	input wire [7:0] kb_dat0,
	input wire [7:0] kb_dat1,
	input wire [7:0] kb_dat2,
	input wire [7:0] kb_dat3,
	input wire [7:0] kb_dat4,
	input wire [7:0] kb_dat5,

	input wire [12:0] joy_l,
	input wire [12:0] joy_r,

	input wire [7:0] matrix_out,
	output wire [7:0] matrix_in,
	output reg restore_n = 1'b1,
	output wire [3:0] joy_n,
	output wire fire_n
);

// ------------------------------------------------------------------ keyboard

reg [3:0] idx = 4'd0;
reg [6:0] code;
reg code_ok;
reg f11_scan = 1'b0;

// the item of this clock
always @(*) begin
	code = 7'd0;
	code_ok = 1'b0;
	case (idx)
	4'd0: begin code = kb_dat0[6:0]; code_ok = !kb_dat0[7]; end
	4'd1: begin code = kb_dat1[6:0]; code_ok = !kb_dat1[7]; end
	4'd2: begin code = kb_dat2[6:0]; code_ok = !kb_dat2[7]; end
	4'd3: begin code = kb_dat3[6:0]; code_ok = !kb_dat3[7]; end
	4'd4: begin code = kb_dat4[6:0]; code_ok = !kb_dat4[7]; end
	4'd5: begin code = kb_dat5[6:0]; code_ok = !kb_dat5[7]; end
	default: begin code = { 4'b1101, idx[2:0] - 3'd6 }; code_ok = kb_status[idx[2:0] - 3'd6]; end
	endcase
end

wire [3:0] km_row, km_row_s;
wire [2:0] km_col, km_col_s;
keymap km (.code(code), .row(km_row), .column(km_col), .row_s(km_row_s), .column_s(km_col_s), .shift_mod(2'b00));
// row 8: no key
wire hit = code_ok && code != 7'd0 && !km_row[3];
wire hit_s = code_ok && code != 7'd0 && !km_row_s[3];

reg [63:0] scan = {64{1'b1}};
reg [63:0] matrix = {64{1'b1}};
wire [63:0] key_bit = hit ? (64'd1 << { km_row[2:0], km_col }) : 64'd0;
wire [63:0] key_bit_s = hit_s ? (64'd1 << { km_row_s[2:0], km_col_s }) : 64'd0;
always @(posedge clk) begin
	if (reset) begin
		idx <= 4'd0;
		scan <= {64{1'b1}};
		matrix <= {64{1'b1}};
		f11_scan <= 1'b0;
		restore_n <= 1'b1;
	end
	else begin
		if (idx < 4'd6 && code_ok && code == 7'h44)
			f11_scan <= 1'b1;
		if (idx == 4'd13) begin
			idx <= 4'd0;
			matrix <= scan & ~key_bit & ~key_bit_s;
			scan <= {64{1'b1}};
			restore_n <= !f11_scan;
			f11_scan <= 1'b0;
		end
		else begin
			idx <= idx + 4'd1;
			scan <= scan & ~key_bit & ~key_bit_s;
		end
	end
end

reg [7:0] mi;
integer r;
always @(*) begin
	mi = 8'hFF;
	for (r = 0; r < 8; r = r + 1)
		if (!matrix_out[r])
			mi = mi & matrix[r*8 +: 8];
end
assign matrix_in = mi;

// ------------------------------------------------------------------ joystick

wire [12:0] j = joy_l | joy_r;
assign joy_n = ~{ j[4], j[3], j[2], j[1] };
assign fire_n = ~(j[6] | j[7]);

endmodule
