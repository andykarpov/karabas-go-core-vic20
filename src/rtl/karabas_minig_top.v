`timescale 1ns / 1ps
`default_nettype wire

/*
 Commodore VIC-20 core for Karabas Mini rev.G (HDMI, PCM5102): the machine of VIC20Nano
 (vic20_core: VIC-20 + C1541 + C1530) with the board glue of karabas-go-modules.

 Clocks (vic20_clk): a DCM_CLKGEN + PLL per standard, a BUFGMUX picks one by the OSD switch Video:
 clk_sys 35.465 MHz PAL / 32.727 MHz NTSC (8 per pixel of the VIC; the machine, the SRAM, the
 MCU link, the video out, audio), clk_x5 / clk_x5_n the serial clock of HDMI. A change of the
 standard resets the machine.

 Memory: char / BASIC / Kernal ROM, 5K RAM, colour RAM, the C1541 in block RAM; the RAM
 expansions and the cartridge RAM in the SRAM (vic20_sram behind extmem).

 Video: the 6561 / 6560 picture (a pixel per 8 clocks, 284 x 312 PAL, 260 x 261 NTSC) through
 scandoubler of VIC20Nano: 1136 x 624 at 35.465 MHz (31.2 kHz, 50.0 Hz, the 576p50 lines) or
 1040 x 522 at 32.727 MHz (31.5 kHz, 60.3 Hz); de: 912 x 576 / 816 x 480 (see the video part).

 Files (FL items, vic20_loader): PRG (slot 1, injected), Cartridge (slot 2), Kernal (slot 4),
 Tape (slot 3: the .tap file in the SRAM from 1 MB, vic20_tape plays it into the C1530).
 Disk 8 (F item, slot 0): the C1541 reads and writes the .d64 (.g64) image through img_sdc.

 Soft switches (the index of the item in the osd of core.json, the "index" of the items):
   6 RAM (None / 3K / 8K / 16K / 24K / 3K+24K / 35K)   7 Video (PAL / NTSC)   8 Disk 8 WP
   9 Tape play   10 Eject cart   11 Reset   12 Keyboard (Symbolic / Positional)
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign TAPE_OUT = 1'b0;
assign ESP32_SPI_CS_N = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;
assign MIDI_TX = 1'b1;
assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

// the SDRAM is not used: NOP commands (RAS / CAS / WE high), its clock low. FLASH_CS_N (T3) is
// the SDRAM /CS of Mini G2 (rev G: tied low on the board): 0, as the cores do.
assign SDR_BA = 2'b00;
assign SDR_A = 13'd0;
assign SDR_CLK = 1'b0;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;
assign FLASH_CS_N = 1'b0;

// ------------------------------------------------------------------ clocks

wire clk_sys, clk_x5, clk_x5_n, locked;
wire sw_ntsc;
reg ntsc = 1'b0;   // the standard of the clock mux, from the switch

vic20_clk clocks (
	.clk_50(CLK_50MHZ),
	.ntsc(ntsc),
	.clk_sys(clk_sys),
	.clk_x5(clk_x5),
	.clk_x5_n(clk_x5_n),
	.locked(locked)
);
wire areset = ~locked;

// the clock of the FT812: clk_sys / 4 (8.87 / 8.18 MHz)
reg [1:0] ft_div = 2'd0;
always @(posedge clk_sys)
	ft_div <= ft_div + 2'd1;
assign FT_CLK_OUT = ft_div[1];

// ------------------------------------------------------------------ MCU

// MCU_SCK on a global buffer (as atarist: on local routing the flip-flops of the SPI receiver had
// several ns of clock skew); the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [7:0] kb_status, kb_dat0, kb_dat1, kb_dat2, kb_dat3, kb_dat4, kb_dat5;
wire [7:0] uart_rx_data, uart_rx_idx, uart_tx_data;
wire uart_tx_wr;
wire [12:0] joy_l, joy_r;
wire [7:0] ms_x, ms_y;
wire [3:0] ms_z;
wire [2:0] ms_b;
wire ms_upd;
wire rom_active, rom_wr;
wire [31:0] rom_addr;
wire [7:0] rom_data;
wire file_active, file_wr;
wire [7:0] file_slot, file_data;
wire [31:0] file_addr;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_mounted, img_data, img_result, img_wp;
wire [63:0] img_size;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;
wire [7:0] rtc_a, rtc_do;

kg_mcu #(
	.BURST_MAX_MHZ(32),  // Rev.G has MCU_SCK on a global clock pin
	.CS_FILTER(3),
	.ENABLE_RTC(0),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),      // Disk 8 (slot 0)
	.ENABLE_IMG_WP(1),   // a read only image: the disk is write protected
	.ENABLE_FILE(1),
	.FILE_CMDS(0),       // the ioctl commands of the FL items
	.FILE_WR_EACH(1),
	.FILE_TO_ROM(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(mcu_sck),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
	.MCU_BURST_READY(mcu_burst_ready),

	.KB_STATUS(kb_status),
	.KB_DAT0(kb_dat0),
	.KB_DAT1(kb_dat1),
	.KB_DAT2(kb_dat2),
	.KB_DAT3(kb_dat3),
	.KB_DAT4(kb_dat4),
	.KB_DAT5(kb_dat5),
	.KB_SCANCODE(),
	.KB_SCANCODE_UPD(),
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_Z(ms_z),
	.MS_B(ms_b),
	.MS_UPD(ms_upd),

	.ROMLOADER_ACTIVE(rom_active),
	.ROMLOAD_ADDR(rom_addr),
	.ROMLOAD_DATA(rom_data),
	.ROMLOAD_WR(rom_wr),

	.FILELOAD_ACTIVE(file_active),
	.FILELOAD_ADDR(file_addr),
	.FILELOAD_DATA(file_data),
	.FILELOAD_WR(file_wr),
	.FILELOAD_SLOT(file_slot),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),
	.BUSY(mcu_busy),

	.FT_SPI_ON(ft_spi_on),
	.FT_CS_N(ft_cs_n),
	.FT_MOSI(ft_mosi),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(),
	.SD2_CS_N(sd2_cs_n),
	.SD2_MOSI(sd2_mosi),
	.SD2_MISO(SD_DO),
	.SD2_SCK(),

	.DVI_ONLY(dvi_only),

	.MIDI_DATA(),
	.MIDI_WR(),
	.MIDI_LOST(),

	// not used by this core
	.PS2_COMMAND(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.RTC_A(rtc_a),
	.RTC_DI(8'd0),
	.RTC_DO(rtc_do),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	.UART_RX_DATA(uart_rx_data),
	.UART_RX_IDX(uart_rx_idx),
	.UART_TX_DATA(uart_tx_data),
	.UART_TX_WR(uart_tx_wr),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),
	.IMG_MOUNTED(img_mounted),
	.IMG_SIZE(img_size),
	.IMG_WP(img_wp),
	.IMG_DATA_WR(img_data_wr),
	.IMG_DATA_ADDR(img_data_addr),
	.IMG_DATA(img_data),
	.IMG_RESULT_WR(img_result_wr),
	.IMG_RESULT(img_result),
	.IMG_SUM(img_sum),
	.IMG_Q_WR(img_q_wr),
	.IMG_Q_DI(img_q_di),
	.IMG_Q_ACK(img_q_ack),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

wire [13*8-1:0] sw;
kg_soft_switches #(.N(13)) soft_switches (
	.clk(clk_sys),
	.command(softsw_command),
	.regs(sw),
	.upd()
);
wire [2:0] sw_ram = sw[6*8 +: 3];
assign sw_ntsc = sw[7*8];
wire sw_disk_wp = sw[8*8];
wire sw_tape_play = sw[9*8];
wire sw_eject = sw[10*8];
wire sw_reset = sw[11*8];
wire sw_positional = sw[12*8];   // Keyboard: 0 Symbolic, 1 Positional

// RAM expansion of the switch, in ram_ext order ($A000, $6000, $4000, $2000, $0400)
reg [4:0] ram_sw;
always @(*)
	case (sw_ram)
	3'd1: ram_sw = 5'b00001;   // 3K
	3'd2: ram_sw = 5'b00010;   // 8K
	3'd3: ram_sw = 5'b00110;   // 16K
	3'd4: ram_sw = 5'b01110;   // 24K
	3'd5: ram_sw = 5'b01111;   // 3K + 24K
	3'd6: ram_sw = 5'b11111;   // 35K: + $A000
	default: ram_sw = 5'b00000;
	endcase

// ------------------------------------------------------------------ reset

// the standard: the clock mux follows the switch, and the machine is reset for 256 clocks
reg [7:0] std_rst = 8'hFF;
always @(posedge clk_sys) begin
	if (areset)
		std_rst <= 8'hFF;
	else if (sw_ntsc != ntsc) begin
		ntsc <= sw_ntsc;
		std_rst <= 8'hFF;
	end
	else if (std_rst != 8'd0)
		std_rst <= std_rst - 8'd1;
end

wire load_reset;
reg eject_d = 1'b0, eject_rst = 1'b0;
always @(posedge clk_sys) begin
	eject_d <= sw_eject;
	eject_rst <= sw_eject && !eject_d;
end
wire vic_reset = areset || sw_reset || mcu_busy || std_rst != 8'd0 || load_reset || eject_rst;

// ------------------------------------------------------------------ loaders

wire conf_wr, lwe;
wire [15:0] conf_ai;
wire [20:0] laddr;
wire [7:0] conf_di, lwdata;
wire [4:0] cart_blk;

vic20_loader loader (
	.clk(clk_sys),
	.reset(areset),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.eject(eject_rst),
	.conf_wr(conf_wr),
	.conf_ai(conf_ai),
	.conf_di(conf_di),
	.lwe(lwe),
	.laddr(laddr),
	.lwdata(lwdata),
	.cart_blk(cart_blk),
	.hold_reset(load_reset)
);

// ------------------------------------------------------------------ tape

wire treq, tack;
wire [20:0] taddr;
wire [7:0] tdata, tap_data;
wire tap_restart, tap_wrreq, tap_wrfull, tap_error, tap_play_stop, cass_run, cass_motor, cass_sense, cass_read;
wire [1:0] tap_version;

vic20_tape tape (
	.clk(clk_sys),
	.reset(vic_reset),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.play(sw_tape_play),
	.treq(treq),
	.taddr(taddr),
	.tdata(tdata),
	.tack(tack),
	.tap_restart(tap_restart),
	.tap_version(tap_version),
	.tap_data(tap_data),
	.tap_wrreq(tap_wrreq),
	.tap_wrfull(tap_wrfull),
	.tap_error(tap_error),
	.cass_run(cass_run),
	.cass_sense(cass_sense),
	.tap_play_stop(tap_play_stop)
);

// ------------------------------------------------------------------ Disk 8

// img_sdc (the file mounter of the mcu) has the sd card interface of MiSTle that c1541_sd of
// VIC20Nano uses: the request held until sdc_busy, the sector bytes as strobes with an address
// while busy; for a write it copies the sector from the track buffer of the C1541, whose data
// come a clock after the address through a mux (OUT_LATENCY 2)
wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
wire [31:0] disk_lba;
wire disk_rd, disk_wr;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, disk_out_data;
wire img_active;

img_sdc #(.OUT_LATENCY(2)) img_sdc (
	.clk(clk_sys),
	.reset(areset),

	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack),

	.sdc_img_mounted(sdc_img_mounted),
	.sdc_img_size(sdc_img_size),
	.sdc_rd({ 7'd0, disk_rd }),
	.sdc_wr({ 7'd0, disk_wr }),
	.sdc_sector(disk_lba),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_error(sdc_error),
	.sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(disk_out_data),

	.active(img_active)
);

// a mount (sdc_img_mounted[0], one clock with the size; size 0 = ejected) is a disk change for
// the C1541; an image of 333744 bytes or more is a G64 (upstream), a change of the kind resets
// the drive
reg disk_change = 1'b0, disk_mount = 1'b0, disk_g64 = 1'b0, disk_g64_d = 1'b0;
always @(posedge clk_sys) begin
	disk_change <= sdc_img_mounted[0];
	disk_g64_d <= disk_g64;
	if (sdc_img_mounted[0]) begin
		disk_mount <= sdc_img_size != 64'd0;
		disk_g64 <= sdc_img_size >= 64'd333744;
	end
end
wire disk_reset = vic_reset || (disk_g64 != disk_g64_d);

// ------------------------------------------------------------------ the machine

wire [3:0] vic_r, vic_g, vic_b;
wire vic_hs, vic_vs, vic_hb, vic_vb;
wire [5:0] vic_audio;
wire [7:0] kbd_matrix_out, kbd_matrix_in;
wire restore_n, fire_n;
wire [3:0] joy_n;
wire extmem_sel, extmem_r_wn;
wire [15:0] extmem_addr;
wire [7:0] extmem_din, extmem_dout;
wire [4:0] ram_ext = ram_sw | cart_blk;
wire [4:0] ram_ext_ro = cart_blk;

vic20_core machine (
	.clk_sys(clk_sys),
	.reset(vic_reset),
	.pal(!ntsc),
	.center(2'b00),
	.wide(1'b0),

	.ce_pix(),
	.video_r(vic_r),
	.video_g(vic_g),
	.video_b(vic_b),
	.hsync(vic_hs),
	.vsync(vic_vs),
	.hblank(vic_hb),
	.vblank(vic_vb),
	.audio(vic_audio),

	.kbd_matrix_out(kbd_matrix_out),
	.kbd_matrix_in(kbd_matrix_in),
	.restore_n(restore_n),

	.joy_n(joy_n),
	.fire_n(fire_n),
	.potx(8'hFF),
	.poty(8'hFF),

	.ram_ext_ro(ram_ext_ro),
	.ram_ext(ram_ext),
	.extmem_sel(extmem_sel),
	.extmem_r_wn(extmem_r_wn),
	.extmem_addr(extmem_addr),
	.extmem_din(extmem_din),
	.extmem_dout(extmem_dout),
	.io2_sel(),
	.io3_sel(),
	.blk123_sel(),
	.blk5_sel(),
	.ram123_sel(),
	.p2h(),

	.conf_wr(conf_wr),
	.conf_ai(conf_ai),
	.conf_di(conf_di),

	// the C1541 on img_sdc (slot 0)
	.disk_reset(disk_reset),
	.disk_pause(1'b0),
	.disk_change(disk_change),
	.disk_mount(disk_mount),
	.disk_readonly(sw_disk_wp || img_wp[0]),
	.disk_g64(disk_g64),
	.disk_led(),
	.sd_lba(disk_lba),
	.sd_rd(disk_rd),
	.sd_wr(disk_wr),
	.sd_ack(sdc_busy && sdc_slot == 3'd0),
	.sd_buff_addr(sdc_byte_addr),
	.sd_buff_dout(sdc_byte_in_data),
	.sd_buff_din(disk_out_data),
	.sd_buff_wr(sdc_byte_in_strobe && sdc_slot == 3'd0),

	// the C1530 (vic20_tape)
	.tap_restart(tap_restart),
	.tap_version(tap_version),
	.tap_data(tap_data),
	.tap_wrreq(tap_wrreq),
	.tap_wrfull(tap_wrfull),
	.tap_error(tap_error),
	.tap_play_stop(tap_play_stop),
	.cass_motor(cass_motor),
	.cass_sense(cass_sense),
	.cass_read(cass_read),
	.cass_run(cass_run),

	.user_port_in(8'hFF),
	.user_port_out(),
	.user_cb1_in(1'b1),
	.user_cb1_out(),
	.user_cb2_in(1'b1),
	.user_cb2_out()
);

// a block of ram_ext_ro (a cartridge) is not written by the machine (vic20.vhd protects only $A000)
wire [2:0] eblk = extmem_addr[15:13];
wire ext_ro = (eblk == 3'd0) ? ram_ext_ro[0] :
              (eblk == 3'd1) ? ram_ext_ro[1] :
              (eblk == 3'd2) ? ram_ext_ro[2] :
              (eblk == 3'd3) ? ram_ext_ro[3] :
              (eblk == 3'd5) ? ram_ext_ro[4] : 1'b0;

vic20_sram sram (
	.clk(clk_sys),
	.caddr({ 5'd0, extmem_addr }),
	.cdata(extmem_din),
	.cwe(extmem_sel && !extmem_r_wn && !ext_ro),
	.cwdata(extmem_dout),
	.treq(treq),
	.taddr(taddr),
	.tdata(tdata),
	.tack(tack),
	.lwe(lwe),
	.laddr(laddr),
	.lwdata(lwdata),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N)
);

vic20_hid hid (
	.clk(clk_sys),
	.reset(areset),
	.kb_status(kb_status),
	.kb_dat0(kb_dat0),
	.kb_dat1(kb_dat1),
	.kb_dat2(kb_dat2),
	.kb_dat3(kb_dat3),
	.kb_dat4(kb_dat4),
	.kb_dat5(kb_dat5),
	.joy_l(joy_l),
	.joy_r(joy_r),
	.symbolic(!sw_positional),
	.matrix_out(kbd_matrix_out),
	.matrix_in(kbd_matrix_in),
	.restore_n(restore_n),
	.joy_n(joy_n),
	.fire_n(fire_n)
);

// ------------------------------------------------------------------ video

// scandoubler of VIC20Nano as its video.v uses it (a sample every 2 clocks, the line doubled)
wire [5:0] sd_r, sd_g, sd_b;
wire sd_hs_n, sd_vs_n, sd_hb;
scandoubler #(.HCNT_WIDTH(10)) doubler (
	.clk_sys(clk_sys),
	.bypass(1'b0),
	.ce_divider(3'd1),
	.pixel_ena(),
	.scanlines(2'b00),
	.hb_in(vic_hb),
	.vb_in(vic_vb),
	.hs_in(vic_hs),
	.vs_in(vic_vs),
	.r_in(vic_r),
	.g_in(vic_g),
	.b_in(vic_b),
	.hb_out(sd_hb),
	.vb_out(),       // lost: its 10-bit sample counter wraps in the 1136 samples of a line
	.hs_out(sd_hs_n),
	.vs_out(sd_vs_n),
	.r_out(sd_r),
	.g_out(sd_g),
	.b_out(sd_b)
);

// The doubled frame (sim/run_boot.sh --geometry), from the leading edges of the syncs:
//   PAL  1136 clocks, hs 80, picture (no hblank) 195..1106; 624 lines, vs 0..7, picture 59..623
//   NTSC 1040 clocks, hs 80, picture 179..994;              522 lines, vs 0..7, picture 35..521
// de: the picture columns, lines 46..621 (576) / 36..515 (480); lines of the vertical blank of
// the VIC inside it are black. The vertical blank: vblank of the VIC at the start of each line.
reg sd_hs_d = 1'b1, sd_vs_d = 1'b1, vs_seen = 1'b0, vb_line = 1'b1;
reg [9:0] vl = 10'd0;
always @(posedge clk_sys) begin
	sd_hs_d <= sd_hs_n;
	sd_vs_d <= sd_vs_n;
	if (sd_vs_d && !sd_vs_n)
		vs_seen <= 1'b1;
	if (sd_hs_d && !sd_hs_n) begin
		vb_line <= vic_vb;
		vl <= vs_seen ? 10'd0 : vl + 10'd1;
		vs_seen <= 1'b0;
	end
end
wire vde = ntsc ? (vl >= 10'd36 && vl < 10'd516) : (vl >= 10'd46 && vl < 10'd622);

reg [23:0] vid_rgb = 24'd0;
reg vid_hs = 1'b0, vid_vs = 1'b0, vid_de = 1'b0;   // syncs high active
always @(posedge clk_sys) begin
	vid_de <= !sd_hb && vde;
	vid_rgb <= (sd_hb || !vde || vb_line) ? 24'd0 : { sd_r, sd_r[5:4], sd_g, sd_g[5:4], sd_b, sd_b[5:4] };
	vid_hs <= !sd_hs_n;
	vid_vs <= !sd_vs_n;
end

// the OSD of the mcu (512 x 416: a step per 2 clocks, per 2 lines) in the middle of de:
//   PAL  clocks 195 + (912 - 512) / 2 = 395, lines 46 + (576 - 416) / 2 = 126
//   NTSC clocks 179 + (816 - 512) / 2 = 331, lines 36 + (480 - 416) / 2 = 68
reg [15:0] osd_cmd = 16'd0;
always @(posedge clk_sys)
	osd_cmd <= osd_command;
wire [23:0] osd_rgb;
kg_osd_overlay #(.H_DIV4_WIDTH(1200), .H_OFFSET_IN(1), .V_OFFSET_IN(1)) osd (
	.clk(clk_sys),
	.rgb_i(vid_rgb),
	.rgb_o(osd_rgb),
	.hsync_i(vid_hs),
	.vsync_i(vid_vs),
	.v_offset(ntsc ? 11'd34 : 11'd63),
	.h_offset(ntsc ? 11'd165 : 11'd197),
	.osd_command(osd_cmd)
);

// ------------------------------------------------------------------ audio

// the 6-bit sound of the VIC (unsigned) as a positive 16-bit sample, a quarter of full scale, and
// the tape signal while it plays (upstream: cass_read with PLAY pressed and the motor on), quiet
wire cass_aud = cass_read && !cass_sense && !cass_motor;
wire [15:0] aud = { 2'b00, vic_audio, 8'd0 } + { 5'd0, cass_aud, 10'd0 };

kg_pcm5102 #(.DIV_BITS(2)) dac (  // bck clk_sys / 8, lrck / 256 (140 / 127 kHz)
	.clk(clk_sys),
	.reset(areset),
	.left(aud),
	.right(aud),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// 48 kHz for hdmi_tx: + 48 per clock, modulo clk_sys / 1000 (35465 / 32727)
wire [15:0] aud_mod = ntsc ? 16'd32727 : 16'd35465;
reg [15:0] aud_acc = 16'd0;
reg aud_stb = 1'b0;
reg [23:0] hdmi_a = 24'd0;
always @(posedge clk_sys) begin
	aud_stb <= 1'b0;
	if (aud_acc >= aud_mod - 16'd48) begin
		aud_acc <= aud_acc + 16'd48 - aud_mod;
		aud_stb <= 1'b1;
		hdmi_a <= { aud, 8'd0 };
	end
	else
		aud_acc <= aud_acc + 16'd48;
end

// ------------------------------------------------------------------ HDMI

// negative syncs (576p / 480p)
hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_sys),
	.sclk(clk_x5),
	.sclk_n(clk_x5_n),
	.reset(areset || std_rst != 8'd0),
	.rgb(osd_rgb),
	.vsync(~vid_vs),
	.hsync(~vid_hs),
	.de(vid_de),
	.audio_en(~dvi_only),
	.audio_l(hdmi_a),
	.audio_r(hdmi_a),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
