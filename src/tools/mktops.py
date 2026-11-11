#!/usr/bin/env python3
"""mktops.py: rtl/karabas_go_top.v and rtl/karabas_mini_top.v from rtl/karabas_minig_top.v.

The Mini G top is the one that is edited; the other two are made from it by this script (run it
after every change of the Mini G top, then build). The port lists are tools/ports/*.v (the pins
of the boards, as core-atarist has them); the body gets the replacements below, each of which
must match exactly once (a change of the Mini G text that one of them depends on fails here,
instead of making a wrong top).

  Mini (before rev.G): MCU_SCK not on a clock pin (no BUFG, bursts at the link clock), MCU_IO 4
      bits, ESP / MIDI / FT reset pins, sigma-delta audio (AUDIO_L / AUDIO_R) instead of the
      PCM5102; HDMI and FT_CLK_OUT as Mini G.
  Go: as Mini for the MCU link, and VGA (24-bit RGB to the DAC, the pixel clock on V_CLK, the
      FT812 off that bus: FT_OE_N = 1) instead of HDMI, PCM5102 with DAC_LRCK / DAC_MUTE, the
      floppy connector unused (its outputs 0: the board inverts them), FLASH_CS_N = 1 (the flash
      chip: the SDRAM /CS is hard wired on Go).
"""
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
rtl = os.path.join(here, '..', 'rtl')
src = open(os.path.join(rtl, 'karabas_minig_top.v')).read()


def sub(s, old, new, what):
    n = s.count(old)
    if n != 1:
        sys.exit('mktops.py: %s: %d matches of %r' % (what, n, old[:80]))
    return s.replace(old, new)


def ports(board):
    return open(os.path.join(here, 'ports', 'karabas_%s_ports.v' % board)).read().rstrip() + '\n'


def common(s, board):
    i = s.index('module karabas_minig_top (')
    j = s.index(');', i) + 3
    s = s[:i] + ports(board) + s[j:]
    s = sub(s, """// MCU_SCK on a global buffer (as atarist: on local routing the flip-flops of the SPI receiver had
// several ns of clock skew); the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));""", """// MCU_SCK is not on a clock pin before rev.G (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;""", 'mcu_sck')
    s = sub(s, "	.BURST_MAX_MHZ(32),  // Rev.G has MCU_SCK on a global clock pin",
            "	.BURST_MAX_MHZ(0),   // MCU_SCK is not on a clock pin: bursts at the link clock", 'burst')
    s = sub(s, "assign ESP32_SPI_CS_N = 1'b1;\n", """assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_RESET_N = 1'b1;
assign MIDI_CLK = 1'b0;
""", 'esp')
    s = sub(s, "assign MIDI_TX = 1'b1;\nassign ADC_CLK = 1'b0;\nassign ADC_BCK = 1'bz;\nassign ADC_LRCK = 1'bz;\n",
            "assign MIDI_TX = 1'b1;\n", 'adc')
    return s


def mini(s):
    s = common(s, 'mini')
    s = sub(s, " Commodore VIC-20 core for Karabas Mini rev.G (HDMI, PCM5102): the machine of VIC20Nano",
            " Commodore VIC-20 core for Karabas Mini before rev.G (HDMI, sigma-delta audio), made from\n"
            " karabas_minig_top.v by tools/mktops.py (edit that one): the machine of VIC20Nano", 'title')
    s = sub(s, "assign MCU_IO[5:2] = 4'bzzzz;", "assign MCU_IO[3:2] = 2'bzz;", 'mcu_io')
    s = sub(s, "assign TAPE_OUT = 1'b0;\n", "assign TAPE_OUT = 1'b0;\nassign FT_RESET = 1'b1;\n", 'ft_reset')
    s = re.sub(r"kg_pcm5102 #\(\.DIV_BITS\(2\)\) dac \(.*?\n\);\n", """// no I2S DAC on this board: sigma-delta outputs into an RC filter, offset binary input
kg_sigma_delta_dac dac_l (.clk(clk_sys), .reset(areset), .din({ ~aud[15], aud[14:0] }), .dout(AUDIO_L));
kg_sigma_delta_dac dac_r (.clk(clk_sys), .reset(areset), .din({ ~aud[15], aud[14:0] }), .dout(AUDIO_R));
""", s, count=1, flags=re.S)
    return s


def go(s):
    s = common(s, 'go')
    s = sub(s, " Commodore VIC-20 core for Karabas Mini rev.G (HDMI, PCM5102): the machine of VIC20Nano",
            " Commodore VIC-20 core for Karabas Go (VGA, PCM5102), made from karabas_minig_top.v by\n"
            " tools/mktops.py (edit that one): the machine of VIC20Nano", 'title')
    s = sub(s, """assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;""", """assign MCU_SPI_IO[0] = mcu_burst_ready;
assign MCU_SPI_IO[1] = 1'bz;""", 'mcu_io')
    s = sub(s, "	.MCU_SPI_FT_SS(MCU_IO[3]),\n	.MCU_SPI_SD2_SS(MCU_IO[2]),\n	.MCU_BURST_CS_N(MCU_IO[0]),",
            "	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),\n	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),\n	.MCU_BURST_CS_N(MCU_SPI_IO[1]),", 'mcu_ss')
    s = sub(s, "assign TAPE_OUT = 1'b0;\n", """assign TAPE_OUT = 1'b0;
assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign BEEPER = 1'b0;

// the floppy connector is not used (a 1541 is an IEC drive): its outputs 0 (the board inverts
// them: high = active)
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b0;
""", 'go pins')
    s = sub(s, """// the SDRAM is not used: NOP commands (RAS / CAS / WE high), its clock low. FLASH_CS_N (T3) is
// the SDRAM /CS of Mini G2 (rev G: tied low on the board): 0, as the cores do.""",
            "// the SDRAM is not used: NOP commands (RAS / CAS / WE high), its clock low. FLASH_CS_N: the\n"
            "// flash chip (the SDRAM /CS is hard wired on Go): 1.", 'sdram comment')
    s = sub(s, "assign FLASH_CS_N = 1'b0;", "assign FLASH_CS_N = 1'b1;", 'flash')
    s = sub(s, """// the clock of the FT812: clk_sys / 4 (8.87 / 8.18 MHz)
reg [1:0] ft_div = 2'd0;
always @(posedge clk_sys)
	ft_div <= ft_div + 2'd1;
assign FT_CLK_OUT = ft_div[1];""", """// the pixel clock of the VGA DAC
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_sys), .C1(~clk_sys), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));""", 'v_clk')
    s = sub(s, ".lrck(DAC_WS)\n);", ".lrck(DAC_LRCK)\n);\nassign DAC_MUTE = 1'b1;  // soft mute of the PCM5102: 1 = sound on", 'dac')
    i = s.index('// 48 kHz for hdmi_tx:')
    j = s.index('endmodule')
    s = s[:i] + """// ------------------------------------------------------------------ VGA

// the syncs negative (576p / 480p lines), the picture of the OSD overlay
assign VGA_R = osd_rgb[23:16];
assign VGA_G = osd_rgb[15:8];
assign VGA_B = osd_rgb[7:0];
assign VGA_HS = ~vid_hs;
assign VGA_VS = ~vid_vs;

""" + s[j:]
    return s


for board, f in (('mini', mini), ('go', go)):
    out = f(src)
    open(os.path.join(rtl, 'karabas_%s_top.v' % board), 'w').write(out)
    print('rtl/karabas_%s_top.v' % board)
