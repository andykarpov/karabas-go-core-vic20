`timescale 1ns / 1ps
`default_nettype wire

/*
 vic20_loader.v

 The files of the FL items (kg_mcu file loader, FILE_CMDS 0, FILE_WR_EACH 1: file_addr = the
 offset in the file, a file_wr per byte) into the VIC-20, as loader_sd_card + the loader process
 of the VIC20Nano top did it from its own SD slots:

   PRG (SLOT_PRG): bytes 0, 1 the load address, then the program: injected into the running
       machine. After the file the BASIC pointers $2D/$2E, $2F/$30, $31/$32 (start of variables,
       arrays, end of arrays) and $AE/$AF (end of load) = the end address, so RUN / LIST work.
       Bytes at $A000 and up are dropped (upstream).
   Cartridge (SLOT_CART): bytes 0, 1 the load address, then the ROM image (8K or more, blocks
       $2000 / $4000 / $6000 / $A000). Each block it touches becomes a read-only RAM block
       (cart_blk -> ram_ext + ram_ext_ro). The machine is held in reset while it loads, so a
       cartridge at $A000 starts by itself (its A0CBM signature). eject clears the blocks (and
       resets).
   Kernal (SLOT_KERNAL): 8K at $E000 of the Kernal RAM (conf $E000-$FFFF), the machine held in
       reset while it loads.

 Where a byte goes: conf_* (clk_sys) writes the block RAM of the machine (0000-03FF, 1000-1FFF,
 the colour RAM 9400-97FF, the Kernal E000-FFFF); the SRAM (lwe) has the expansions 0400-0FFF,
 2000-7FFF and A000-BFFF.
*/

module vic20_loader #(
	parameter [7:0] SLOT_PRG = 8'd1,
	parameter [7:0] SLOT_CART = 8'd2,
	parameter [7:0] SLOT_KERNAL = 8'd4
) (
	input wire clk,
	input wire reset,

	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,
	input wire eject,

	output reg conf_wr = 1'b0,
	output reg [15:0] conf_ai = 16'd0,
	output reg [7:0] conf_di = 8'd0,

	output reg lwe = 1'b0,
	output reg [15:0] laddr = 16'd0,
	output reg [7:0] lwdata = 8'd0,

	output reg [4:0] cart_blk = 5'd0,   // $A000, $6000, $4000, $2000, $0400 (ram_ext order)
	output wire hold_reset              // a cartridge or a Kernal loading
);

wire is_prg = file_slot == SLOT_PRG;
wire is_cart = file_slot == SLOT_CART;
wire is_kernal = file_slot == SLOT_KERNAL;

reg [15:0] addr = 16'd0;            // the next address of a PRG / cartridge
reg active_d = 1'b0;
reg [3:0] ptr = 4'd0;               // the pointer writes after a PRG: 1..8

assign hold_reset = file_active && (is_cart || is_kernal);

// the expansion RAM / cartridge areas (SRAM)
function in_sram;
	input [15:0] a;
	in_sram = (a[15:12] != 4'h0 || a[11:10] != 2'b00) && a[15:12] < 4'h1 ||   // 0400-0FFF
	          a[15:13] == 3'd1 || a[15:13] == 3'd2 || a[15:13] == 3'd3 ||       // 2000-7FFF
	          a[15:13] == 3'd5;                                                // A000-BFFF
endfunction

// the block of an address in ram_ext order
function [4:0] blk_of;
	input [15:0] a;
	case (a[15:13])
	3'd0: blk_of = 5'b00001;
	3'd1: blk_of = 5'b00010;
	3'd2: blk_of = 5'b00100;
	3'd3: blk_of = 5'b01000;
	3'd5: blk_of = 5'b10000;
	default: blk_of = 5'b00000;
	endcase
endfunction

always @(posedge clk) begin
	conf_wr <= 1'b0;
	lwe <= 1'b0;
	active_d <= file_active;

	if (reset) begin
		ptr <= 4'd0;
	end
	else if (file_wr && file_active) begin
		if (file_addr == 32'd0)
			addr[7:0] <= file_data;
		else if (file_addr == 32'd1)
			addr[15:8] <= file_data;
		else if (is_kernal) begin
			if (file_addr < 32'h2000) begin
				conf_ai <= { 3'b111, file_addr[12:0] };
				conf_di <= file_data;
				conf_wr <= 1'b1;
			end
		end
		if ((is_prg || is_cart) && file_addr >= 32'd2) begin
			if (is_prg ? addr < 16'hA000 : addr < 16'hC000) begin
				if (in_sram(addr)) begin
					laddr <= addr;
					lwdata <= file_data;
					lwe <= 1'b1;
				end
				else if (is_prg) begin
					conf_ai <= addr;
					conf_di <= file_data;
					conf_wr <= 1'b1;
				end
				if (is_cart)
					cart_blk <= cart_blk | blk_of(addr);
				addr <= addr + 16'd1;
			end
		end
		// a Kernal file starts at offset 0 (no load address): the two first bytes too
		if (is_kernal && file_addr < 32'd2) begin
			conf_ai <= { 3'b111, 11'd0, file_addr[1:0] };
			conf_di <= file_data;
			conf_wr <= 1'b1;
		end
	end

	// a new cartridge: the blocks of the old one go
	if (file_active && !active_d && is_cart)
		cart_blk <= 5'd0;
	if (eject)
		cart_blk <= 5'd0;

	// the end of a PRG: the pointers (one write every other clock)
	if (!file_active && active_d && is_prg)
		ptr <= 4'd1;
	else if (ptr != 4'd0 && !conf_wr) begin
		case (ptr)
		4'd1: conf_ai <= 16'h002D;
		4'd2: conf_ai <= 16'h002E;
		4'd3: conf_ai <= 16'h002F;
		4'd4: conf_ai <= 16'h0030;
		4'd5: conf_ai <= 16'h0031;
		4'd6: conf_ai <= 16'h0032;
		4'd7: conf_ai <= 16'h00AE;
		default: conf_ai <= 16'h00AF;
		endcase
		conf_di <= ptr[0] ? addr[7:0] : addr[15:8];
		conf_wr <= 1'b1;
		ptr <= (ptr == 4'd8) ? 4'd0 : ptr + 4'd1;
	end
end

endmodule
