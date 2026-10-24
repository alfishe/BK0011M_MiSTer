//
// sim_main.cpp
//
// Runs the core from power-on and writes chosen frames as PPM files.
//
//   obj_dir/Vsim_top frames every [options...]
//
// frames      how many frames to run (50 a second)
// every       write one frame in this many
//
// options:
//   F:KEY       press a key at frame F, let it go KEY_HOLD_FRAMES later; KEY
//               is a PS/2 set 2 code in hex, E0xx for an extended one
//   t=F:TEXT    type TEXT from frame F: letters, digits, space . , / - ; : @
//               '|' is Enter
//   jF:HEX      set the gamepad's buttons (hps_io joystick_0 bits) at frame F
//   iIDX=PATH   download a file at start-up with ioctl index IDX (hex):
//               0 is bk0011m.rom, 1 a .BIN; iIDX@F=PATH downloads it at
//               frame F instead
//   dN=PATH     put an image in slot N: 0 the hard disk, 1-4 the floppy
//               drives A-D; dN@F=PATH mounts it at frame F instead of at
//               start-up (the OSD's mount)
//   oN=PATH     write slot N's image to PATH at the end
//   ro=N        mount slot N read-only
//   pfx=PATH    prefix of the frame files (default "frame")
//   lat=US      the HPS's delay before a sector transfer (default 200 us)
//   +sdlog      print every sector transfer
//   +status=HEX the OSD's status bits (hex), zero without
//
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "Vsim_top.h"
#include "verilated.h"

static const int  RESET_CYCLES     = 100;
static const int  MAX_W            = 1024;
static const int  MAX_H            = 1024;
static const int  KEY_HOLD_FRAMES  = 5;
static const int  TYPE_HOLD_FRAMES = 2;   // a typed key is down this long
static const int  TYPE_STEP_FRAMES = 4;   // and the next one comes this much later
static const int  EXT_PREFIX       = 0xE0;
static const char ENTER_CHAR       = '|';

static const long CLK_HZ           = 96000000;   // clk_sys
static const int  DEFAULT_LAT_US   = 200;
static const int  DRIVES           = 5;   // image slots
static const int  HDD              = 0;
static const int  SECTOR_WORDS     = 256;
static const int  SECTOR_BYTES     = 512;
static const int  WORD_CYCLES      = 8;   // clk_sys cycles per buffer word
static const int  GAP_CYCLES       = 100; // between two transfers

// hps_io's ps2_key: [10] toggles per event, [9] pressed, [8] extended
static const int PS2_TOGGLE  = 1 << 10;
static const int PS2_PRESSED = 1 << 9;
static const int PS2_EXT     = 1 << 8;

static const int PS2_ENTER   = 0x5A;
static const int PS2_LSHIFT  = 0x12;
static const int SHIFTED     = 0x1000;   // ps2_of: hold shift for this one

struct KeyEvent { int frame; int code; bool pressed; };
struct PadEvent { int frame; unsigned buttons; };
struct Download { int index; std::vector<unsigned char> data; int frame = 0; };

static const int DOWNLOAD_WORD_CYCLES = 8;   // clk_sys cycles per ioctl word

static bool read_file(const char *path, std::vector<unsigned char> &data)
{
   FILE *fp = fopen(path, "rb");
   if(!fp) { perror(path); return false; }
   fseek(fp, 0, SEEK_END); data.resize(ftell(fp)); fseek(fp, 0, SEEK_SET);
   bool ok = fread(data.data(), 1, data.size(), fp) == data.size();
   if(!ok) perror(path);
   fclose(fp);
   return ok;
}

static int ps2_of(char c)
{
   static const unsigned char letters[26] = {
      0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
      0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A };
   static const unsigned char digits[10] = {
      0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46 };
   if(c >= 'a' && c <= 'z') c -= 'a' - 'A';
   if(c >= 'A' && c <= 'Z') return letters[c - 'A'];
   if(c >= '0' && c <= '9') return digits[c - '0'];
   switch(c) {
   case ' ': return 0x29;
   case '.': return 0x49;
   case ',': return 0x41;
   case '/': return 0x4A;
   case '-': return 0x4E;
   case ';': return 0x4C;
   case ':': return SHIFTED | 0x4C;
   case '@': return 0x0E;   // ` key: the BK's @
   case ENTER_CHAR: return PS2_ENTER;
   }
   return 0;
}

// The HPS side of the sector interface
struct Disk {
   std::vector<unsigned char> data;
   std::string save;
   bool ro = false;
   int  frame = 0;      // mounted at this frame (0: at start-up)
};

enum HpsState { HPS_IDLE, HPS_LATENCY, HPS_READ, HPS_WRITE, HPS_GAP };

struct Hps {
   Disk     disk[DRIVES];
   HpsState state = HPS_IDLE;
   long     wait = 0;
   long     latency = 0;
   int      drive = 0, word = 0, phase = 0;
   unsigned lba = 0;
   bool     log = false;
   long     reads = 0, writes = 0;

   unsigned char *sector()
   {
      size_t off = (size_t)lba * SECTOR_BYTES;
      return off + SECTOR_BYTES <= disk[drive].data.size() ? &disk[drive].data[off] : nullptr;
   }

   // one clk_sys cycle, before the rising edge
   void step(Vsim_top *top)
   {
      top->sd_buff_wr = 0;
      switch(state) {
      case HPS_IDLE: {
         int req = top->sd_rd | top->sd_wr;
         if(!req) break;
         for(int i = 0; i < DRIVES; i++) if(req & (1 << i)) {
            drive = i;
            lba   = i == HDD ? top->sd_lba_hdd : top->sd_lba;
            break;
         }
         phase = (top->sd_wr >> drive) & 1;   // remember the direction
         if(log) printf("hps: %s slot %d lba %u%s\n", phase ? "write" : "read", drive, lba, sector() ? "" : " (outside the image)");
         wait  = latency;
         state = HPS_LATENCY;
         break;
      }
      case HPS_LATENCY:
         if(--wait > 0) break;
         top->sd_ack = 1 << drive;
         word  = 0;
         wait  = WORD_CYCLES;
         state = phase ? HPS_WRITE : HPS_READ;
         break;
      case HPS_READ: {
         if(--wait > 0) break;
         wait = WORD_CYCLES;
         unsigned char *s = sector();
         top->sd_buff_addr = word;
         top->sd_buff_dout = s ? s[word * 2] | s[word * 2 + 1] << 8 : 0;
         top->sd_buff_wr   = 1;
         if(++word == SECTOR_WORDS) { state = HPS_GAP; wait = GAP_CYCLES; reads++; }
         break;
      }
      case HPS_WRITE: {
         // the address goes out, the core's registered buffer answers a cycle later
         if(phase == 1) { top->sd_buff_addr = word; phase = 2; wait = WORD_CYCLES; break; }
         if(--wait > 0) break;
         unsigned din = drive == HDD ? top->sd_buff_din_hdd : top->sd_buff_din;
         unsigned char *s = sector();
         if(s && !disk[drive].ro) { s[word * 2] = din & 0xFF; s[word * 2 + 1] = din >> 8; }
         if(++word == SECTOR_WORDS) { state = HPS_GAP; wait = GAP_CYCLES; writes++; }
         else { top->sd_buff_addr = word; wait = WORD_CYCLES; }
         break;
      }
      case HPS_GAP:
         top->sd_ack = 0;
         if(--wait > 0) break;
         state = HPS_IDLE;
         break;
      }
   }
};

int main(int argc, char **argv)
{
   Verilated::commandArgs(argc, argv);
   if(argc < 3) { fprintf(stderr, "usage: %s frames every [options]\n", argv[0]); return 1; }
   const int frames = atoi(argv[1]);
   const int every  = atoi(argv[2]);

   Hps hps;
   int lat_us = DEFAULT_LAT_US;
   std::string pfx = "frame";
   std::vector<KeyEvent> keys;
   std::vector<PadEvent> pads;
   std::vector<Download> downloads;

   for(int i = 3; i < argc; i++) {
      const char *a = argv[i];
      int f, k, n;
      if(!strcmp(a, "+sdlog")) hps.log = true;
      else if(!strncmp(a, "lat=", 4)) lat_us = atoi(a + 4);
      else if(!strncmp(a, "pfx=", 4)) pfx = a + 4;
      else if(!strncmp(a, "ro=", 3)) { int d = atoi(a + 3); if(d >= 0 && d < DRIVES) hps.disk[d].ro = true; }
      else if((a[0] == 'd' || a[0] == 'o') && a[1] >= '0' && a[1] < '0' + DRIVES && (a[2] == '=' || a[2] == '@')) {
         Disk &d = hps.disk[a[1] - '0'];
         const char *path = a + 3;
         if(a[2] == '@') { d.frame = atoi(a + 3); path = strchr(a + 3, '='); if(!path) { fprintf(stderr, "bad %s\n", a); return 1; } path++; }
         if(a[0] == 'o') { d.save = path; continue; }
         if(!read_file(path, d.data)) return 1;
      }
      else if(a[0] == 'i' && (n = 0, sscanf(a + 1, "%x=%n", &k, &n)) == 1 && n) {
         downloads.push_back({k, {}});
         if(!read_file(a + 1 + n, downloads.back().data)) return 1;
      }
      else if(a[0] == 'i' && (n = 0, sscanf(a + 1, "%x@%d=%n", &k, &f, &n)) == 2 && n) {
         downloads.push_back({k, {}, f});
         if(!read_file(a + 1 + n, downloads.back().data)) return 1;
      }
      else if(a[0] == 'j' && sscanf(a + 1, "%d:%x", &f, &k) == 2) pads.push_back({f, (unsigned)k});
      else if(!strncmp(a, "t=", 2) && sscanf(a + 2, "%d:%n", &f, &n) == 1) {
         for(const char *c = a + 2 + n; *c; c++, f += TYPE_STEP_FRAMES) {
            int code = ps2_of(*c);
            if(!code) { fprintf(stderr, "can't type '%c'\n", *c); return 1; }
            if(code & SHIFTED) {
               code &= ~SHIFTED;
               keys.push_back({f, PS2_LSHIFT, true});
               keys.push_back({f + 1, code, true});
               keys.push_back({f + TYPE_HOLD_FRAMES, code, false});
               keys.push_back({f + TYPE_HOLD_FRAMES + 1, PS2_LSHIFT, false});
            } else {
               keys.push_back({f, code, true});
               keys.push_back({f + TYPE_HOLD_FRAMES, code, false});
            }
         }
      }
      else if(sscanf(a, "%d:%x", &f, &k) == 2) {
         int code = (k >> 8) == EXT_PREFIX ? PS2_EXT | (k & 0xFF) : k & 0xFF;
         keys.push_back({f, code, true});
         keys.push_back({f + KEY_HOLD_FRAMES, code, false});
      }
      else if(a[0] != '+') { fprintf(stderr, "unknown option %s\n", a); return 1; }
   }
   hps.latency = CLK_HZ / 1000000 * lat_us;

   Vsim_top *top = new Vsim_top;
   std::vector<unsigned char> fb(MAX_W * MAX_H * 3);

   int x = 0, y = 0, w = 0, h = 0, frame = 0;
   bool old_vs = false, old_de = false;
   long cycle = 0;

   top->RESET   = 1;
   top->ps2_key = 0;
   top->joystick = 0;
   top->ioctl_download = 0;
   top->ioctl_wr = 0;
   top->img_mounted = 0;
   top->img_readonly = 0;
   top->sd_ack = 0;

   auto tick = [&]() {
      hps.step(top);
      top->CLK_50M = 0; top->eval();
      top->CLK_50M = 1; top->eval();
      top->img_mounted = 0;
      cycle++;
   };

   // the HPS sends a file a word at a time
   auto download = [&](const Download &dl) {
      top->ioctl_index    = dl.index;
      top->ioctl_download = 1;
      for(size_t b = 0; b < dl.data.size(); b += 2) {
         top->ioctl_addr = b;
         top->ioctl_dout = dl.data[b] | (b + 1 < dl.data.size() ? dl.data[b + 1] << 8 : 0);
         top->ioctl_wr   = 1;
         tick();
         top->ioctl_wr   = 0;
         for(int c = 1; c < DOWNLOAD_WORD_CYCLES; c++) tick();
      }
      top->ioctl_download = 0;
      tick();
   };

   while(frame < frames && !Verilated::gotFinish()) {
      tick();
      if(cycle == RESET_CYCLES) {
         top->RESET = 0;
         // the files the HPS sends when the core starts
         for(const Download &dl : downloads) if(dl.frame == 0) download(dl);
         // mount the images, one drive per cycle as the HPS does
         for(int i = 0; i < DRIVES; i++) if(!hps.disk[i].data.empty() && hps.disk[i].frame == 0) {
            top->img_size     = hps.disk[i].data.size();
            top->img_readonly = hps.disk[i].ro;
            top->img_mounted  = 1 << i;
            tick();
         }
      }

      if(!top->CE_PIXEL) continue;

      if(top->VGA_DE) {
         if(x < MAX_W && y < MAX_H) {
            unsigned char *p = &fb[(y * MAX_W + x) * 3];
            p[0] = top->VGA_R; p[1] = top->VGA_G; p[2] = top->VGA_B;
         }
         x++;
      }
      else if(old_de) {
         if(x > w) w = x;
         x = 0;
         y++;
      }
      old_de = top->VGA_DE;

      if(top->VGA_VS && !old_vs) {
         h = y;
         if(frame % every == every - 1 && w && h) {
            char name[1024];
            snprintf(name, sizeof name, "%s%04d.ppm", pfx.c_str(), frame);
            FILE *f = fopen(name, "wb");
            fprintf(f, "P6\n%d %d\n255\n", w, h);
            for(int r = 0; r < h; r++) fwrite(&fb[r * MAX_W * 3], 3, w, f);
            fclose(f);
            printf("%s %dx%d sd reads %ld writes %ld\n", name, w, h, hps.reads, hps.writes);
            fflush(stdout);
         }
         frame++;
         for(const Download &dl : downloads) if(dl.frame == frame) download(dl);
         for(int i = 0; i < DRIVES; i++) if(!hps.disk[i].data.empty() && hps.disk[i].frame == frame) {
            top->img_size     = hps.disk[i].data.size();
            top->img_readonly = hps.disk[i].ro;
            top->img_mounted  = 1 << i;
            tick();
         }
         for(const KeyEvent &e : keys) if(e.frame == frame) {
            top->ps2_key = ((top->ps2_key ^ PS2_TOGGLE) & PS2_TOGGLE) |
                           (e.pressed ? PS2_PRESSED : 0) | e.code;
            // one event per clk_sys edge at most: let this one be seen
            tick(); tick();
         }
         for(const PadEvent &e : pads) if(e.frame == frame) top->joystick = e.buttons;
         x = y = 0;
      }
      old_vs = top->VGA_VS;
   }

   for(int i = 0; i < DRIVES; i++) if(!hps.disk[i].save.empty()) {
      FILE *fp = fopen(hps.disk[i].save.c_str(), "wb");
      fwrite(hps.disk[i].data.data(), 1, hps.disk[i].data.size(), fp);
      fclose(fp);
   }
   printf("sd reads %ld writes %ld\n", hps.reads, hps.writes);

   delete top;
   return 0;
}
