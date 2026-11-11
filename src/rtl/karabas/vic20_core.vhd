--
-- vic20_core.vhd (karabas)
--
-- The VIC-20 of VIC20Nano without the board: the machine (vic20.vhd: T65, 6561 / 6560, two
-- 6522, 5K RAM + colour RAM, char / BASIC / Kernal ROM), the C1541 drive (c1541_sd: 6502 + two
-- 6522, GCR, track buffer, DOS ROM 325302-01 / 901229-06AA here in block RAM) on the IEC bus and
-- the C1530 tape player (c1530, TAP from a FIFO). What upstream does in its board top
-- (vic20nano_top_tn20k.vhd) and is not board specific is here: the clock enable of the machine,
-- the IEC wiring.
--
-- The board top gives:
--  * clk_sys: 8 clocks per pixel of the VIC (PAL 35.47 MHz, NTSC 32.73 MHz; upstream 35.775 /
--    32.94); the C1541 counts 32 of them per 1 MHz cycle, as upstream does;
--  * the memory behind extmem_*: the RAM expansions, the cartridge RAM, IO2 / IO3 (later the
--    Mega-Cart): i_extmem_en is 1 in this core (vic20.vhd has no expansion RAM in block RAM);
--    read data in the clock after extmem_sel, like a block RAM, or held for the whole p2 phase;
--  * conf_*: writes into the RAM and the Kernal of the machine (PRG injection, Kernal file);
--  * sd_*: the sector interface of the C1541 (img_sdc of modules/rtl/mcu, as MiSTle sd_card).
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vic20_core is
  port (
    clk_sys       : in  std_logic;
    reset         : in  std_logic;  -- machine
    pal           : in  std_logic;  -- 1 PAL 6561, 0 NTSC 6560
    center        : in  std_logic_vector(1 downto 0);
    wide          : in  std_logic;

    -- video, in clk_sys, a pixel every 8 clocks (ce_pix)
    ce_pix        : out std_logic;
    video_r       : out std_logic_vector(3 downto 0);
    video_g       : out std_logic_vector(3 downto 0);
    video_b       : out std_logic_vector(3 downto 0);
    hsync         : out std_logic;
    vsync         : out std_logic;
    hblank        : out std_logic;
    vblank        : out std_logic;
    audio         : out std_logic_vector(5 downto 0);

    -- keyboard matrix (vic20_keyboard: out = column select, in = rows, low active)
    kbd_matrix_out: out std_logic_vector(7 downto 0);
    kbd_matrix_in : in  std_logic_vector(7 downto 0);
    restore_n     : in  std_logic;  -- the RESTORE key, low = pressed (VIA1 CA1 -> NMI)

    -- joystick (low active: 0 up, 1 down, 2 left, 3 right), fire, paddles
    joy_n         : in  std_logic_vector(3 downto 0);
    fire_n        : in  std_logic;
    potx          : in  std_logic_vector(7 downto 0);
    poty          : in  std_logic_vector(7 downto 0);

    -- external memory
    ram_ext_ro    : in  std_logic_vector(4 downto 0);
    ram_ext       : in  std_logic_vector(4 downto 0); -- $A000, $6000, $4000, $2000, $0400 (3K)
    extmem_sel    : out std_logic;
    extmem_r_wn   : out std_logic;
    extmem_addr   : out std_logic_vector(15 downto 0);
    extmem_din    : in  std_logic_vector(7 downto 0);
    extmem_dout   : out std_logic_vector(7 downto 0);
    io2_sel       : out std_logic;
    io3_sel       : out std_logic;
    blk123_sel    : out std_logic;
    blk5_sel      : out std_logic;
    ram123_sel    : out std_logic;
    p2h           : out std_logic;

    -- configuration writes (clk_sys)
    conf_wr       : in  std_logic;
    conf_ai       : in  std_logic_vector(15 downto 0);
    conf_di       : in  std_logic_vector(7 downto 0);

    -- C1541
    disk_reset    : in  std_logic;
    disk_pause    : in  std_logic;
    disk_change   : in  std_logic;
    disk_mount    : in  std_logic;
    disk_readonly : in  std_logic;
    disk_g64      : in  std_logic;
    disk_led      : out std_logic;
    sd_lba        : out std_logic_vector(31 downto 0);
    sd_rd         : out std_logic;
    sd_wr         : out std_logic;
    sd_ack        : in  std_logic;
    sd_buff_addr  : in  std_logic_vector(8 downto 0);
    sd_buff_dout  : in  std_logic_vector(7 downto 0);
    sd_buff_din   : out std_logic_vector(7 downto 0);
    sd_buff_wr    : in  std_logic;

    -- C1530
    tap_restart   : in  std_logic;
    tap_version   : in  std_logic_vector(1 downto 0);
    tap_data      : in  std_logic_vector(7 downto 0);
    tap_wrreq     : in  std_logic;
    tap_wrfull    : out std_logic;
    tap_play_stop : in  std_logic;  -- toggle
    cass_motor    : out std_logic;  -- 0 = motor on
    cass_sense    : out std_logic;
    cass_read     : out std_logic;
    cass_run      : out std_logic;

    -- user port
    user_port_in  : in  std_logic_vector(7 downto 0);
    user_port_out : out std_logic_vector(7 downto 0);
    user_cb1_in   : in  std_logic;
    user_cb1_out  : out std_logic;
    user_cb2_in   : in  std_logic;
    user_cb2_out  : out std_logic
  );
end;

architecture rtl of vic20_core is

  component kg_sprom
    generic (
      DW        : integer := 8;
      AW        : integer := 10;
      INIT_FILE : string  := ""
    );
    port (
      clk  : in  std_logic;
      en   : in  std_logic;
      addr : in  std_logic_vector(AW-1 downto 0);
      dout : out std_logic_vector(DW-1 downto 0)
    );
  end component;

  signal div4          : unsigned(1 downto 0) := "00";
  signal sysclk_en     : std_logic := '0';

  signal iec_atn_o     : std_logic;
  signal iec_clk_o     : std_logic;
  signal iec_data_o    : std_logic;
  signal iec_atn_d     : std_logic;
  signal iec_clk_d     : std_logic;
  signal iec_data_d    : std_logic;

  signal c1541rom_addr : std_logic_vector(14 downto 0);
  signal c1541rom_a14  : std_logic_vector(13 downto 0);
  signal c1541rom_data : std_logic_vector(7 downto 0);
  signal c1541rom_cs   : std_logic;

  signal cass_write    : std_logic;
  signal motor         : std_logic;
  signal sense         : std_logic;
  signal tape_read     : std_logic;

begin

  -- the 8.9 MHz enable of the machine: one clock in four (upstream video.v, there on the falling
  -- edge of clk32)
  process (clk_sys)
  begin
    if rising_edge(clk_sys) then
      div4 <= div4 + 1;
      if div4 = "00" then
        sysclk_en <= '1';
      else
        sysclk_en <= '0';
      end if;
    end if;
  end process;

  vic : entity work.VIC20
    port map (
      i_sysclk      => clk_sys,
      i_sysclk_en   => sysclk_en,
      i_reset       => reset,
      o_p2h         => p2h,

      atn_o         => iec_atn_o,
      clk_o         => iec_clk_o,
      clk_i         => iec_clk_d,
      data_o        => iec_data_o,
      data_i        => iec_data_d,

      i_joy         => joy_n,
      i_fire        => fire_n,
      i_potx        => potx,
      i_poty        => poty,

      i_ram_ext_ro  => ram_ext_ro,
      i_ram_ext     => ram_ext,

      i_extmem_en   => '1',
      o_extmem_sel  => extmem_sel,
      o_extmem_r_wn => extmem_r_wn,
      o_extmem_addr => extmem_addr,
      i_extmem_data => extmem_din,
      o_extmem_data => extmem_dout,
      o_io2_sel     => io2_sel,
      o_io3_sel     => io3_sel,
      o_blk123_sel  => blk123_sel,
      o_blk5_sel    => blk5_sel,
      o_ram123_sel  => ram123_sel,

      o_ce_pix      => ce_pix,
      o_video_r     => video_r,
      o_video_g     => video_g,
      o_video_b     => video_b,
      o_hsync       => hsync,
      o_vsync       => vsync,
      o_hblank      => hblank,
      o_vblank      => vblank,
      i_center      => center,
      i_pal         => pal,
      i_wide        => wide,

      ps2_key       => (others => '0'),
      i_restore_n   => restore_n,
      keyboard_matrix_out => kbd_matrix_out,
      keyboard_matrix_in  => kbd_matrix_in,
      tape_play     => open,

      o_audio       => audio,

      cass_write    => cass_write,
      cass_read     => tape_read,
      cass_motor    => motor,
      cass_sw       => sense,

      rom_std       => '1',
      conf_clk      => clk_sys,
      conf_wr       => conf_wr,
      conf_ai       => conf_ai,
      conf_di       => conf_di,

      user_port_cb1_in  => user_cb1_in,
      user_port_cb1_out => user_cb1_out,
      user_port_cb2_in  => user_cb2_in,
      user_port_cb2_out => user_cb2_out,
      user_port_in      => user_port_in,
      user_port_out     => user_port_out
    );

  -- the drive outputs are open collector lines as seen by the VIC (1 = released), as in upstream
  c1541 : entity work.c1541_sd
    port map (
      clk32         => clk_sys,
      reset         => disk_reset,
      pause         => disk_pause,
      ce            => '0',
      disk_num      => (others => '0'),
      disk_change   => disk_change,
      disk_mount    => disk_mount,
      disk_readonly => disk_readonly,
      disk_g64      => disk_g64,

      iec_atn_i     => iec_atn_o,
      iec_data_i    => iec_data_o,
      iec_clk_i     => iec_clk_o,
      iec_atn_o     => iec_atn_d,
      iec_data_o    => iec_data_d,
      iec_clk_o     => iec_clk_d,

      sd_lba        => sd_lba,
      sd_rd         => sd_rd,
      sd_wr         => sd_wr,
      sd_ack        => sd_ack,
      sd_buff_addr  => sd_buff_addr,
      sd_buff_dout  => sd_buff_dout,
      sd_buff_din   => sd_buff_din,
      sd_buff_wr    => sd_buff_wr,

      led           => disk_led,

      par_data_i    => "11111111",
      par_stb_i     => '1',
      par_data_o    => open,
      par_stb_o     => open,

      ext_en        => '0',
      c1541rom_addr => c1541rom_addr,
      c1541rom_data => c1541rom_data,
      c1541rom_cs   => c1541rom_cs
    );

  -- DOS ROM $C000-$FFFF (upstream reads 32K banks of the SPI flash: CBM, Dolphin, SpeedDOS,
  -- JiffyDOS; the others come later as user files). Read every clock: the data are there
  -- long before the cpu takes them (16 clocks after c1541rom_cs).
  c1541rom_a14 <= c1541rom_addr(13 downto 0);

  c1541_rom : kg_sprom
    generic map (DW => 8, AW => 14, INIT_FILE => "rom/c1541-325302-01_901229-06aa.hex")
    port map (
      clk  => clk_sys,
      en   => '1',
      addr => c1541rom_a14,
      dout => c1541rom_data
    );

  tape : entity work.c1530
    port map (
      clk32           => clk_sys,
      restart_tape    => tap_restart,
      wav_mode        => '0',
      tap_version     => tap_version,
      host_tap_in     => tap_data,
      host_tap_wrreq  => tap_wrreq,
      tap_fifo_wrfull => tap_wrfull,
      tap_fifo_error  => open,
      osd_play_stop_toggle => tap_play_stop,
      cass_sense      => sense,
      cass_read       => tape_read,
      cass_write      => cass_write,
      cass_motor      => motor,
      cass_run        => cass_run,
      ear_input       => '0'
    );

  cass_motor <= motor;
  cass_sense <= sense;
  cass_read  <= tape_read;

end rtl;
