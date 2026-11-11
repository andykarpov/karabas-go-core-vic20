`timescale 1ns / 1ps
`default_nettype wire

/*
 vic20_sram.v

 The SRAM of the board (two 2M x 8 chips = 2M x 16, 10 ns, asynchronous) as the external memory
 of the VIC-20 (extmem of vic20.vhd: the RAM expansions $0400-$0FFF, $2000-$7FFF, the cartridge
 RAM $A000-$BFFF, later the Mega-Cart) and for the loaders of the mcu, which write bytes.
 Byte address = { MA, lane }, lane 0 = MD[7:0] (MWR_N[0], MRD_N[0]); the addresses here are 21
 bits (the first 2 MB of the 4 MB, MA[20] = 0); the VIC space is the first 64K.

 Slots of three clocks (28 ns at 35.8 MHz, 84 ns per slot):
 - read: MA = the address of the machine, MD taken two clocks later; one after the other, so
   rdata follows a new address within seven clocks. The 6502 of the VIC takes its data at the
   end of its 32-clock cycle, the address is stable from its start.
 - write: /OE of both chips off (MRD_N = 11), MD driven for three clocks, /WE of the lane low in
   the middle one. A write of the loader (lwe: one clock, a byte per microsecond or less often)
   goes first; a write of the machine (cwe: held for the p2 half of its cycle) is repeated in
   every slot while cwe holds (the same byte at the same address; the address may change at the
   end of p2, a new address then gets its own data).
 - a read for the tape player (treq held until tack): a read slot of its own between two of the
   machine (the machine then waits one slot more: within ten clocks).
*/

module vic20_sram (
	input wire clk,

	input wire [20:0] caddr,      // byte address of the machine
	output wire [7:0] cdata,      // its byte, from the last read slot
	input wire cwe,
	input wire [7:0] cwdata,

	input wire treq,              // a read of the tape player, held until tack
	input wire [20:0] taddr,
	output reg [7:0] tdata = 8'd0,
	output reg tack = 1'b0,

	input wire lwe,               // a byte of a loader (one clock)
	input wire [20:0] laddr,
	input wire [7:0] lwdata,

	output reg [20:0] MA = 21'd0, // word address; [20] = 0
	inout wire [15:0] MD,
	output reg [1:0] MWR_N = 2'b11,
	output reg [1:0] MRD_N = 2'b00
);

reg [15:0] rword = 16'hFFFF;
reg rlane = 1'b0;
assign cdata = rlane ? rword[15:8] : rword[7:0];

reg lpend = 1'b0;
reg [20:0] lp_addr = 21'd0;
reg [7:0] lp_data = 8'd0;

reg md_oe = 1'b0;
reg [15:0] md_out = 16'd0;
reg [2:0] st = 3'd0;
reg s_lane = 1'b0;
reg [20:0] r_addr = 21'd0;
reg r_tape = 1'b0, t_last = 1'b0;   // this read slot is the tape's; the last one was

localparam S_IDLE = 3'd0, S_R1 = 3'd1, S_R2 = 3'd2, S_W1 = 3'd3, S_W2 = 3'd4, S_W3 = 3'd5;

assign MD = md_oe ? md_out : 16'bz;

always @(posedge clk) begin
	tack <= 1'b0;
	case (st)
	S_IDLE:
		if (lpend || cwe) begin
			MA <= { 1'b0, lpend ? lp_addr[20:1] : caddr[20:1] };
			s_lane <= lpend ? lp_addr[0] : caddr[0];
			md_out <= lpend ? { lp_data, lp_data } : { cwdata, cwdata };
			lpend <= 1'b0;
			md_oe <= 1'b1;
			MRD_N <= 2'b11;
			st <= S_W1;
		end
		else if (treq && !t_last && !tack) begin
			MA <= { 1'b0, taddr[20:1] };
			r_addr <= taddr;
			r_tape <= 1'b1;
			t_last <= 1'b1;
			st <= S_R1;
		end
		else begin
			MA <= { 1'b0, caddr[20:1] };
			r_addr <= caddr;
			r_tape <= 1'b0;
			t_last <= 1'b0;
			st <= S_R1;
		end
	S_R1:
		st <= S_R2;
	S_R2: begin
		// two clocks after the address (an IOB register can take MD)
		if (r_tape) begin
			tdata <= r_addr[0] ? MD[15:8] : MD[7:0];
			tack <= 1'b1;
		end
		else begin
			rword <= MD;
			rlane <= r_addr[0];
		end
		st <= S_IDLE;
	end
	S_W1: begin
		MWR_N <= s_lane ? 2'b01 : 2'b10;
		st <= S_W2;
	end
	S_W2: begin
		MWR_N <= 2'b11;
		st <= S_W3;
	end
	default: begin  // S_W3
		md_oe <= 1'b0;
		MRD_N <= 2'b00;
		st <= S_IDLE;
	end
	endcase

	// a new byte of a loader (after the case: it wins over the clear of the slot that takes the old one)
	if (lwe) begin
		lpend <= 1'b1;
		lp_addr <= laddr;
		lp_data <= lwdata;
	end
end

endmodule
