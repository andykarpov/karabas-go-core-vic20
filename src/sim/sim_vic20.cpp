// sim_vic20.cpp: the verilator harness of tb_vic20 (vic20_core + the external memory).
//
//   clk_sys 35.484 MHz (PAL, DCM 50 * 22 / 31) or 32.759 MHz (NTSC, 50 * 19 / 29)
//   keyboard: the VIC-20 matrix (row = bit of kbd_matrix_out = VIA2 port B, column = bit of
//             kbd_matrix_in = VIA2 port A), from text typed at a time
//   SD card: the sector interface of img_sdc / MiSTle sd_card for the C1541 (one .d64)
//   frames: the picture of the 6561 (ce_pix pixels outside the blanking) as PPM, and the text of
//           the screen read back from it with the character ROM (--text)
//
// options:
//   --ms N             run N ms of machine time (default 2000)
//   --ntsc             6560 and the NTSC clock
//   --ram MASK         ram_ext (bit 0 $0400 3K, 1..3 $2000 / $4000 / $6000, 4 $A000), hex
//   --d64 F            .d64 image in drive 8, mounted at 10 ms
//   --type-at MS TEXT  type TEXT (\n = Return) from MS on
//   --prg-at MS F      inject the .prg F at MS (conf writes, then the BASIC pointers, as upstream)
//   --ppm PREFIX       write the last frame to PREFIX.ppm
//   --text             print the screen text of the last frame
//   --expect TEXT      exit 1 unless the last screen contains TEXT
//   --trace-sd         print the SD requests
#include "Vtb_vic20.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static Vtb_vic20 *top;
static uint64_t cycles = 0;
static double SYS_HZ = 50e6 * 22 / 31;
static uint64_t ms_to_cycles(double ms) { return (uint64_t)(ms * SYS_HZ / 1000.0); }
static double now_ms() { return cycles * 1000.0 / SYS_HZ; }

// ---------------------------------------------------------------- SD card
static FILE *d64 = nullptr;
static bool trace_sd = false;
enum SdState { SD_IDLE, SD_READ, SD_WRITE, SD_DONE };
static SdState sd_state = SD_IDLE;
static int sd_pos = 0, sd_wait = 0;
static uint8_t sd_buf[512];
static uint32_t sd_lba_cur = 0;
static int sd_reads = 0, sd_writes = 0;

static void sd_step() {
	top->sd_buff_wr = 0;
	switch (sd_state) {
	case SD_IDLE:
		if (top->sd_rd || top->sd_wr) {
			bool rd = top->sd_rd;
			sd_lba_cur = top->sd_lba;
			if (trace_sd) printf("[%8.3f ms] SD %s lba %u\n", now_ms(), rd ? "rd" : "wr", sd_lba_cur);
			memset(sd_buf, 0, sizeof sd_buf);
			if (rd && d64) {
				fseek(d64, (long)sd_lba_cur * 512, SEEK_SET);
				size_t n = fread(sd_buf, 1, 512, d64);
				(void)n;
			}
			rd ? sd_reads++ : sd_writes++;
			top->sd_ack = 1;
			sd_state = rd ? SD_READ : SD_WRITE;
			sd_pos = 0;
			sd_wait = 8;
		}
		break;
	case SD_READ:
		if (sd_wait) { sd_wait--; break; }
		top->sd_buff_addr = sd_pos;
		top->sd_buff_dout = sd_buf[sd_pos];
		top->sd_buff_wr = 1;
		sd_wait = 3;
		if (++sd_pos == 512) { sd_state = SD_DONE; sd_wait = 8; }
		break;
	case SD_WRITE:
		// index n, its byte two clocks later (track buffer latency + the output mux)
		if (sd_wait) {
			if (sd_wait == 1 && sd_pos > 0) sd_buf[sd_pos - 1] = top->sd_buff_din;
			sd_wait--;
			break;
		}
		if (sd_pos == 512) {
			if (d64) {
				fseek(d64, (long)sd_lba_cur * 512, SEEK_SET);
				fwrite(sd_buf, 1, 512, d64);
				fflush(d64);
			}
			sd_state = SD_DONE;
			sd_wait = 8;
			break;
		}
		top->sd_buff_addr = sd_pos++;
		sd_wait = 2;
		break;
	case SD_DONE:
		if (sd_wait) { sd_wait--; break; }
		top->sd_ack = 0;
		sd_state = SD_IDLE;
		break;
	}
}

// ---------------------------------------------------------------- keyboard
// matrix position = row * 8 + column (row: kbd_matrix_out bit, column: kbd_matrix_in bit)
#define K(r, c) ((r) * 8 + (c))
static const int K_LSHIFT = K(3, 1);
struct KeyEv { uint64_t at; int pos; bool down; };
static std::vector<KeyEv> keys;
static size_t key_next = 0;
static bool pressed[64];

static bool ascii_key(char c, int &pos, bool &shift) {
	shift = false;
	static const char *letters = "abcdefghijklmnopqrstuvwxyz";
	static const int lpos[26] = { K(2,1), K(4,3), K(4,2), K(2,2), K(6,1), K(5,2), K(2,3), K(5,3), K(1,4),
		K(2,4), K(5,4), K(2,5), K(4,4), K(3,4), K(6,4), K(1,5), K(6,0), K(1,2), K(5,1), K(6,2),
		K(6,3), K(3,3), K(1,1), K(3,2), K(1,3), K(4,1) };
	// 1..9, 0
	static const int dpos[10] = { K(7,4), K(0,0), K(7,0), K(0,1), K(7,1), K(0,2), K(7,2), K(0,3), K(7,3), K(0,4) };
	if (c >= 'A' && c <= 'Z') c = c - 'A' + 'a';
	if (const char *p = strchr(letters, c); p && c) { pos = lpos[p - letters]; return true; }
	if (c >= '0' && c <= '9') { pos = dpos[c - '0']; return true; }
	switch (c) {
	case '\n': pos = K(1, 7); return true;
	case ' ': pos = K(4, 0); return true;
	case ',': pos = K(3, 5); return true;
	case '.': pos = K(4, 5); return true;
	case '/': pos = K(3, 6); return true;
	case ':': pos = K(5, 5); return true;
	case ';': pos = K(2, 6); return true;
	case '=': pos = K(5, 6); return true;
	case '+': pos = K(0, 5); return true;
	case '-': pos = K(7, 5); return true;
	case '*': pos = K(1, 6); return true;
	case '@': pos = K(6, 5); return true;
	case '"': pos = dpos[2]; shift = true; return true;
	case '$': pos = dpos[4]; shift = true; return true;
	case '(': pos = dpos[8]; shift = true; return true;
	case ')': pos = dpos[9]; shift = true; return true;
	}
	return false;
}

static void type_text(double at_ms, const char *text) {
	uint64_t t = ms_to_cycles(at_ms);
	const uint64_t step = ms_to_cycles(40);   // the Kernal scans the keyboard every 1/60 s
	for (const char *p = text; *p; p++) {
		char c = *p;
		if (c == '\\' && p[1] == 'n') { c = '\n'; p++; }
		int pos; bool shift;
		if (!ascii_key(c, pos, shift)) continue;
		if (shift) { keys.push_back({t, K_LSHIFT, true}); t += step / 2; }
		keys.push_back({t, pos, true}); t += step;
		keys.push_back({t, pos, false}); t += step / 2;
		if (shift) { keys.push_back({t, K_LSHIFT, false}); t += step / 2; }
		t += step / 2;
	}
}

static void key_step() {
	while (key_next < keys.size() && cycles >= keys[key_next].at) {
		pressed[keys[key_next].pos] = keys[key_next].down;
		key_next++;
	}
	uint8_t out = top->kbd_matrix_out, in = 0xFF;
	for (int r = 0; r < 8; r++)
		if (!(out >> r & 1))
			for (int c = 0; c < 8; c++)
				if (pressed[K(r, c)]) in &= ~(1 << c);
	top->kbd_matrix_in = in;
}

// ---------------------------------------------------------------- PRG injection
// as the loader of upstream (vicnano top): bytes 2.. at the load address, then $2D/$2F/$31 and
// $AE = the end address
struct Conf { uint16_t a; uint8_t d; };
static std::vector<Conf> conf;
static size_t conf_next = 0;
static uint64_t conf_at = 0;
static int conf_gap = 0;

static bool load_prg(const char *name) {
	FILE *f = fopen(name, "rb");
	if (!f) return false;
	std::vector<uint8_t> b;
	int c;
	while ((c = fgetc(f)) != EOF) b.push_back(c);
	fclose(f);
	if (b.size() < 3) return false;
	uint16_t a = b[0] | b[1] << 8;
	for (size_t i = 2; i < b.size() && a < 0xA000; i++) conf.push_back({a++, b[i]});
	const uint16_t ptrs[] = { 0x2D, 0x2F, 0x31, 0xAE };
	for (uint16_t p : ptrs) { conf.push_back({p, (uint8_t)a}); conf.push_back({(uint16_t)(p + 1), (uint8_t)(a >> 8)}); }
	printf("prg %s: %zu bytes, end %04x\n", name, b.size() - 2, a);
	return true;
}

static void conf_step() {
	top->conf_wr = 0;
	if (conf_next >= conf.size() || cycles < conf_at) return;
	if (conf_gap) { conf_gap--; return; }
	top->conf_ai = conf[conf_next].a;
	top->conf_di = conf[conf_next].d;
	top->conf_wr = 1;
	conf_next++;
	conf_gap = 3;
}

// ---------------------------------------------------------------- frames
static const int FW = 320, FH = 320;
static int fx = 0, fy = 0, frames = 0;
static bool old_hb = false, old_vb = false, line_lit = false;

static std::vector<uint16_t> frame_rgb(FW * FH), last_rgb(FW * FH);

static void pixel_step() {
	if (!top->ce_pix) return;
	bool hb = top->hblank, vb = top->vblank;
	if (!hb && !vb && fx < FW && fy < FH) {
		frame_rgb[fy * FW + fx] = top->video_r << 8 | top->video_g << 4 | top->video_b;
		line_lit = true;
	}
	if (!hb) fx++;
	if (hb && !old_hb) { if (line_lit) fy++; fx = 0; line_lit = false; }
	if (vb && !old_vb) {
		last_rgb = frame_rgb;
		std::fill(frame_rgb.begin(), frame_rgb.end(), 0);
		fy = 0;
		frames++;
	}
	old_hb = hb; old_vb = vb;
}

static void write_ppm(const std::string &name) {
	FILE *f = fopen(name.c_str(), "wb");
	if (!f) return;
	fprintf(f, "P6\n%d %d\n255\n", FW, FH);
	for (int i = 0; i < FW * FH; i++) {
		uint16_t c = last_rgb[i];
		uint8_t p[3] = { (uint8_t)((c >> 8 & 15) * 17), (uint8_t)((c >> 4 & 15) * 17), (uint8_t)((c & 15) * 17) };
		fwrite(p, 1, 3, f);
	}
	fclose(f);
}

// the text of the screen: the window of the background colour inside the border, 8 x 8 cells
// matched against the character ROM (first 2K: upper case / graphics, screen codes 0..127, and
// their inverse 128..255)
static std::vector<uint8_t> chargen;
static std::string screen_text() {
	if (chargen.empty()) {
		FILE *f = fopen("rom/characters.901460-03.bin", "rb");
		if (!f) return "(no rom/characters.901460-03.bin)";
		chargen.resize(4096);
		size_t n = fread(chargen.data(), 1, 4096, f);
		(void)n;
		fclose(f);
	}
	// border = the colour of the first pixel; the screen = the bounding box of the rest
	uint16_t border = last_rgb[FW * 2 + 2];
	int x0 = FW, y0 = FH, x1 = -1, y1 = -1;
	for (int y = 0; y < FH; y++)
		for (int x = 0; x < FW; x++)
			if (last_rgb[y * FW + x] != border && last_rgb[y * FW + x] != 0) {
				if (x < x0) x0 = x;
				if (y < y0) y0 = y;
				if (x > x1) x1 = x;
				if (y > y1) y1 = y;
			}
	if (x1 < 0) return "(blank screen)";
	// the background: the most common colour in the box
	std::vector<int> cnt(4096);
	for (int y = y0; y <= y1; y++)
		for (int x = x0; x <= x1; x++) cnt[last_rgb[y * FW + x]]++;
	int bg = 0;
	for (int i = 0; i < 4096; i++) if (cnt[i] > cnt[bg]) bg = i;
	int cols = (x1 - x0 + 1) / 8, rows = (y1 - y0 + 1) / 8;
	std::string s;
	for (int r = 0; r < rows; r++) {
		std::string line;
		for (int c = 0; c < cols; c++) {
			uint8_t g[8];
			for (int y = 0; y < 8; y++) {
				g[y] = 0;
				for (int x = 0; x < 8; x++)
					if (last_rgb[(y0 + r * 8 + y) * FW + x0 + c * 8 + x] != bg) g[y] |= 0x80 >> x;
			}
			int code = -1;
			for (int k = 0; k < 256 && code < 0; k++) {
				bool ok = true;
				for (int y = 0; y < 8 && ok; y++) ok = chargen[(k & 127) * 8 + y] == (k & 128 ? (uint8_t)~g[y] : g[y]);
				if (ok) code = k;
			}
			char ch = '?';
			if (code >= 0) {
				int k = code & 127;
				ch = k == 0 ? '@' : k < 27 ? 'A' + k - 1 : k == 27 ? '[' : k == 29 ? ']' : k >= 32 && k < 64 ? k : '#';
				if (code & 128) ch = k == 32 ? '_' : ch;  // the cursor
			}
			line += ch;
		}
		while (!line.empty() && line.back() == ' ') line.pop_back();
		s += line + "\n";
	}
	return s;
}

// ---------------------------------------------------------------- main
int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	double run_ms = 2000, prg_ms = 0;
	std::string ppm, expect;
	const char *d64name = nullptr, *prg = nullptr;
	bool ntsc = false, text = false;
	unsigned ram = 0;
	struct T { double ms; std::string s; };
	std::vector<T> typed;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		if (a == "--ms" && i + 1 < argc) run_ms = atof(argv[++i]);
		else if (a == "--ntsc") ntsc = true;
		else if (a == "--ram" && i + 1 < argc) ram = strtoul(argv[++i], nullptr, 16);
		else if (a == "--d64" && i + 1 < argc) d64name = argv[++i];
		else if (a == "--type-at" && i + 2 < argc) { double t = atof(argv[++i]); typed.push_back({t, argv[++i]}); }
		else if (a == "--prg-at" && i + 2 < argc) { prg_ms = atof(argv[++i]); prg = argv[++i]; }
		else if (a == "--ppm" && i + 1 < argc) ppm = argv[++i];
		else if (a == "--text") text = true;
		else if (a == "--expect" && i + 1 < argc) expect = argv[++i];
		else if (a == "--trace-sd") trace_sd = true;
		else { fprintf(stderr, "unknown option %s\n", argv[i]); return 2; }
	}
	if (ntsc) SYS_HZ = 50e6 * 19 / 29;
	for (auto &t : typed) type_text(t.ms, t.s.c_str());
	if (prg) {
		if (!load_prg(prg)) { fprintf(stderr, "can't read %s\n", prg); return 1; }
		conf_at = ms_to_cycles(prg_ms);
	}
	if (d64name && !(d64 = fopen(d64name, "r+b"))) { fprintf(stderr, "can't open %s\n", d64name); return 1; }

	top = new Vtb_vic20;
	top->pal = !ntsc;
	top->ram_ext = ram;
	top->ram_ext_ro = 0;
	top->joy_n = 0xF;
	top->fire_n = 1;
	top->reset = 1;
	top->disk_reset = 1;
	top->disk_readonly = 0;
	top->kbd_matrix_in = 0xFF;
	top->clk_sys = 0;
	top->eval();

	const uint64_t end = ms_to_cycles(run_ms), mount_at = ms_to_cycles(10);
	while (cycles < end && !Verilated::gotFinish()) {
		top->clk_sys = 1;
		top->eval();
		pixel_step();
		cycles++;

		if (cycles == ms_to_cycles(1)) { top->reset = 0; top->disk_reset = 0; }
		top->disk_change = 0;
		if (d64 && cycles == mount_at) { top->disk_mount = 1; top->disk_change = 1; }
		sd_step();
		key_step();
		conf_step();

		top->clk_sys = 0;
		top->eval();
	}
	printf("%.1f ms, %d frames, sd reads %d writes %d, disk led %d\n", now_ms(), frames, sd_reads, sd_writes, top->disk_led);
	if (!ppm.empty()) write_ppm(ppm + ".ppm");
	std::string scr = screen_text();
	if (text) fputs(scr.c_str(), stdout);
	int rc = 0;
	if (!expect.empty()) {
		bool ok = scr.find(expect) != std::string::npos;
		printf("expect \"%s\": %s\n", expect.c_str(), ok ? "ok" : "MISSING");
		rc = ok ? 0 : 1;
	}
	if (d64) fclose(d64);
	top->final();
	delete top;
	return rc;
}
