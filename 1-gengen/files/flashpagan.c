#include <stdbool.h>
#include <inttypes.h>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <mpsse.h>

#include <time.h>

#define assure(what_expr)                                               \
  if (!(what_expr)) { assure_failed(__FILE__, __LINE__); } else { }

static void assure_failed(char const * file, int line)
{
  fprintf(stderr, "fail: (%s) [%d]\n", file, line);
  exit(1);
  while (1);
}

struct mpsse_context* frob;
char frob_byte;

#define ENTER() assure((Start (frob)) == MPSSE_OK)
#define LEAVE() assure((Stop  (frob)) == MPSSE_OK)

#define TX(what_valu)     assure((FastWrite (frob, ((frob_byte = (what_valu)), &frob_byte) , 1) == MPSSE_OK));
#define RX()          (({ assure((FastRead  (frob,                             &frob_byte  , 1) == MPSSE_OK)); }), frob_byte)

#define RXIU() (((int)(RX())) & 0xFF)

static int FastWriteConst(struct mpsse_context* frob, char const* buf, int len)
{
  return FastWrite(frob, ((char*)(buf)), len);
}

static int status(int cmd)
{
  ENTER();
  TX(cmd);
  int rv = RXIU();
  LEAVE();
  return rv;
}

static int status1(void)
{
  return status(0x05);
}

static int status2(void)
{
  return status(0x35);
}

static void writeenable(void)
{
  ENTER();
  TX(0x06);
  LEAVE();
}

static void waitready(void)
{
  int i = 0;
  
  while (((status1() & 0x1) == 0x1)) {
    if ((i++) == 0) {
      fprintf(stderr, "waitready (busy) ...\n");
    }
  }
  
  if (i != 0) {
    fprintf(stderr, "waitready completed after %d polling iteration(s)\n", i);
  }
}

static void chiperase(void)
{
  writeenable();
  
  ENTER();
  TX(0x60);
  LEAVE();

  waitready();
}

static int allfs(char const * buf, int len)
{
  int x = 0xFF;
  
  for (int i = 0; i < len; i++) {
    x &= (((int)(buf[i])) & 0xFF);
  }
  
  return (x == 0xFF);
}

static char const * narg(int* argc, char const *const ** argv)
{
  assure(((*argc)--) > 0);
  return (*((*argv)++));
}

#define RETRIES                                                         \
  int retries = 0;                                                      \
retry:                                                                  \
 if (retries++ > 10) { fprintf(stderr, "too many retries %s %d", __FUNCTION__, __LINE__); exit(1); }

static void read_page_robust(int size_page, char* page, int addr_page)
{
  RETRIES;
  ENTER();
  TX(0x03);
  TX((addr_page >> 16));
  TX((addr_page >>  8));
  TX((addr_page      ));
  assure((FastRead(frob, page, size_page) == MPSSE_OK));
  LEAVE();
  for (int i = 0; i < 3; i++) {
    char page_scan[size_page];
    ENTER();
    TX(0x03);
    TX((addr_page >> 16));
    TX((addr_page >>  8));
    TX((addr_page      ));
    assure((FastRead(frob, page_scan, size_page) == MPSSE_OK));
    LEAVE();
    if (!(memcmp(page_scan, page, size_page) == 0)) {
      goto retry;
    }
  }
}

static void read_sector_robust(int size_page, int size_sector, char* sector, int addr_sector)
{
  for (int addr_page = addr_sector; addr_page < (addr_sector + size_sector); addr_page += size_page) {
    read_page_robust(size_page, (sector + (addr_page - addr_sector)), addr_page);
  }
}

static void write_sector_oneshot(int size_page, int size_sector, char const* sector, int addr_sector)
{
  fprintf(stderr,   "erasing sector:   0x%08X\n", addr_sector);
  {
    writeenable();
    ENTER();
    TX(0x20);
    TX((addr_sector >> 16));
    TX((addr_sector >>  8));
    TX((addr_sector      ));
    LEAVE();
    waitready();
  }
  for (int addr_page = addr_sector; addr_page < (addr_sector + size_sector); addr_page += size_page) {
    char const* page = (sector + (addr_page - addr_sector));
    fprintf(stderr, "programming page: 0x%08X\n", addr_page);
    writeenable();
    ENTER();
    TX(0x02);
    TX((addr_page >> 16));
    TX((addr_page >>  8));
    TX((addr_page      ));
    assure((FastWriteConst(frob, page, size_page) == MPSSE_OK));
    LEAVE();
    waitready();
  }
}

static bool flash_robust_converge(int size_page, int size_sector, int size_chip, char const* image, int* written)
{
  bool good = true;
  
  for (int addr_sector = 0; addr_sector < size_chip; addr_sector += size_sector) {
    char const* sector = (image + addr_sector);
    char sector_scan[size_sector];
    fprintf(stderr, "probing sector:   0x%08X\n", addr_sector);
    read_sector_robust(size_page, size_sector, sector_scan, addr_sector);
    if (!(memcmp(sector_scan, sector, size_sector) == 0)) {
      good = false;
      (*written)++;
      write_sector_oneshot(size_page, size_sector, sector, addr_sector);
    }
  }
  
  return good;
}

static void flash_robust(int size_page, int size_sector, int size_chip, char const* image)
{
  int written_i = 0;
  int written_a[4096];
  memset(written_a, 0, sizeof(written_a));
  RETRIES;
  assure(((size_t)(written_i)) < (sizeof(written_a)/sizeof(written_a[0])));
  fprintf(stderr, "whole image recheck\n");
  if (!(flash_robust_converge(size_page, size_sector, size_chip, image, (&(written_a[written_i++]))))) {
    fprintf(stderr, "sectors written sequence:\n");
    for (int i = 0; i < written_i; i++) {
      fprintf(stderr, "%d\n", written_a[i]);
    }
    goto retry;
  }
}

#define NARG() narg(&argc, &argv)

int main(int argc, char const *const * argv)
{
  NARG();
  
  int PAGESIZE = atoi(NARG());
  int CHIPSIZE = atoi(NARG());
  int SPISPEED = atoi(NARG());
  
  char const* cmd = NARG();
  
  assure(((frob = MPSSE(SPI0, SPISPEED, MSB)) != NULL));
  assure((frob->open == 1));
  
  /****/ if (strcmp(cmd, "status") == 0) {
    fprintf(stderr, "st1=0x%02X\n", status1());
  } else if (strcmp(cmd, "status2") == 0) {
    fprintf(stderr, "st2=0x%02X\n", status2());
  } else if (strcmp(cmd, "status12") == 0) {
    fprintf(stderr, "st1=0x%02X st2=0x%02X\n", status1(), status2());
  } else if (strcmp(cmd, "statuswr") == 0) {
    int st1 = (atoi(NARG()) & 0xFF);
    int st2 = (atoi(NARG()) & 0xFF);
    writeenable();
    ENTER();
    TX(0x01);
    TX(st1);
    TX(st2);
    LEAVE();
  } else if (strcmp(cmd, "read") == 0) {
    char buf[PAGESIZE];
    FILE *const f = fopen("out.bin", "wb");
    assure((f != NULL));
    ENTER();
    TX(0x03);
    TX(0x00);
    TX(0x00);
    TX(0x00);
    for (int i = 0; i < (CHIPSIZE/PAGESIZE); i++) {
      fprintf(stderr, "reading address: 0x%08X\n", (i*PAGESIZE));
      assure((FastRead(frob, buf, PAGESIZE) == MPSSE_OK));
      assure(fwrite(buf, PAGESIZE, 1, f) == 1);
    }
    LEAVE();
    fclose(f);
  } else if (strcmp(cmd, "readpages") == 0) {
    char buf[PAGESIZE];
    FILE *const f = fopen("out.bin", "wb");
    assure((f != NULL));
    for (int i = 0; i < (CHIPSIZE/PAGESIZE); i++) {
      int pa = (i*PAGESIZE);
      fprintf(stderr, "reading address: 0x%08X\n", (i*PAGESIZE));
      ENTER();
      TX(0x03);
      TX((pa >> 16));
      TX((pa >>  8));
      TX((pa      ));
      assure((FastRead(frob, buf, PAGESIZE) == MPSSE_OK));
      LEAVE();
      assure(fwrite(buf, PAGESIZE, 1, f) == 1);
    }
    fclose(f);
  } else if (strcmp(cmd, "readpagesrobust") == 0) {
    FILE *const f = fopen("out.bin", "wb");
    assure((f != NULL));
    for (int i = 0; i < (CHIPSIZE/PAGESIZE); i++) {
      int pa = (i*PAGESIZE);
      fprintf(stderr, "reading address: 0x%08X\n", pa);
      char buf1[PAGESIZE];
      read_page_robust(PAGESIZE, buf1, pa);
      assure(fwrite(buf1, PAGESIZE, 1, f) == 1);
    }
    fclose(f);
  } else if (strcmp(cmd, "erase") == 0) {
    chiperase();
  } else if (strcmp(cmd, "flash") == 0) {
    char buf[PAGESIZE];
    FILE *const f = fopen("inp.bin", "rb");
    assure((f != NULL));
    {
      fprintf(stderr, "chiperase\n");
      chiperase();
    }
    {
      assure((CHIPSIZE == ((CHIPSIZE/PAGESIZE)*PAGESIZE)));
      for (int i = 0; i < (CHIPSIZE/PAGESIZE); i++) {
        int a = (i*PAGESIZE);
        assure((fread(buf, PAGESIZE, 1, f) == 1));
        if (!(allfs(buf, PAGESIZE))) {
          fprintf(stderr, "programming address: 0x%08X\n", a);
          writeenable();
          ENTER();
          TX(0x02);
          TX((a >> 16));
          TX((a >>  8));
          TX((a      ));
          assure((FastWrite(frob, buf, PAGESIZE) == MPSSE_OK));
          LEAVE();
          waitready();
        } else {
          fprintf(stderr, "skipping address: 0x%08X\n", a);
        }
      }
    }
    fclose(f);
  } else if (strcmp(cmd, "flashverify") == 0) {
    char buf[PAGESIZE];
    FILE *const f = fopen("inp.bin", "rb");
    assure((f != NULL));
    {
      fprintf(stderr, "chiperase\n");
      chiperase();
    }
    {
      assure((CHIPSIZE == ((CHIPSIZE/PAGESIZE)*PAGESIZE)));
      for (int i = 0; i < (CHIPSIZE/PAGESIZE); i++) {
        int a = (i*PAGESIZE);
        assure((fread(buf, PAGESIZE, 1, f) == 1));
        if (!(allfs(buf, PAGESIZE))) {
          fprintf(stderr, "programming address: 0x%08X\n", a);
          writeenable();
          ENTER();
          TX(0x02);
          TX((a >> 16));
          TX((a >>  8));
          TX((a      ));
          assure((FastWrite(frob, buf, PAGESIZE) == MPSSE_OK));
          LEAVE();
          waitready();
          fprintf(stderr, "verifying address: 0x%08X\n", a);
          ENTER();
          TX(0x03);
          TX((a >> 16));
          TX((a >>  8));
          TX((a      ));
          char buf2[PAGESIZE];
          assure((FastRead(frob, buf2, PAGESIZE) == MPSSE_OK));
          LEAVE();
          if (!(memcmp(buf2, buf, PAGESIZE) == 0)) {
            fprintf(stderr, "verification failed!\n");
            exit(1);
          }
        } else {
          fprintf(stderr, "skipping address: 0x%08X\n", a);
        }
      }
    }
    fclose(f);
  } else if (strcmp(cmd, "flashsectors") == 0) {
    FILE *const f = fopen("inp.bin", "rb");
    assure((f != NULL));
    assure((CHIPSIZE == ((CHIPSIZE/PAGESIZE)*PAGESIZE)));
    int const SECTORSIZE = 4096;
    assure((CHIPSIZE == ((CHIPSIZE/SECTORSIZE)*SECTORSIZE)));
    int totalretries = 0;
    for (int j = 0; j < (CHIPSIZE/SECTORSIZE); j++) {
      int as = (j*SECTORSIZE);
      char bufin[SECTORSIZE];
      assure((fread(bufin, SECTORSIZE, 1, f) == 1));
      int retries = 0;
    retrysector:
      if (!(retries++ < 10)) { fprintf(stderr, "too many retries, giving up\n"); exit(1); }
      fprintf(stderr,   "erasing sector:   0x%08X (retries so far %d)\n", as, totalretries);
      writeenable();
      ENTER();
      TX(0x20);
      TX((as >> 16));
      TX((as >>  8));
      TX((as      ));
      LEAVE();
      waitready();
      for (int i = 0; i < (SECTORSIZE/PAGESIZE); i++) {
        int ap = (as + (i*PAGESIZE));
        char* bufinpage = (bufin + (i*PAGESIZE));
        fprintf(stderr, "programming page: 0x%08X (retries so far %d)\n", ap, totalretries);
        writeenable();
        ENTER();
        TX(0x02);
        TX((ap >> 16));
        TX((ap >>  8));
        TX((ap      ));
        assure((FastWrite(frob, bufinpage, PAGESIZE) == MPSSE_OK));
        LEAVE();
        waitready();
        fprintf(stderr, "verifying page:   0x%08X (retries so far %d)\n", ap, totalretries);
        char bufropage[PAGESIZE];
        ENTER();
        TX(0x03);
        TX((ap >> 16));
        TX((ap >>  8));
        TX((ap      ));
        assure((FastRead(frob, bufropage, PAGESIZE) == MPSSE_OK));
        LEAVE();
        for (int k = 0; k < PAGESIZE; k++) {
          if (bufropage[k] != bufinpage[k]) {
            fprintf(stderr, "error at byte %d, retrying\n", k);
            totalretries++;
            goto retrysector;
          }
        }
      }
    }
    fprintf(stderr, "total retries %d\n", totalretries);
    fclose(f);
  } else if (strcmp(cmd, "flashsectorsnf") == 0) {
    FILE *const f = fopen("inp.bin", "rb");
    assure((f != NULL));
    assure((CHIPSIZE == ((CHIPSIZE/PAGESIZE)*PAGESIZE)));
    int const SECTORSIZE = 4096;
    assure((CHIPSIZE == ((CHIPSIZE/SECTORSIZE)*SECTORSIZE)));
    {
      fprintf(stderr, "chiperase\n");
      chiperase();
    }
    for (int j = 0; j < (CHIPSIZE/SECTORSIZE); j++) {
      int as = (j*SECTORSIZE);
      char bufin[SECTORSIZE];
      assure((fread(bufin, SECTORSIZE, 1, f) == 1));
      if (allfs(bufin, SECTORSIZE)) continue;
      int retries = 0;
    retrysectornf:
      if (!(retries++ < 10)) { fprintf(stderr, "too many retries, giving up\n"); exit(1); }
      fprintf(stderr, "erasing sector: 0x%08X\n", as);
      writeenable();
      ENTER();
      TX(0x20);
      TX((as >> 16));
      TX((as >>  8));
      TX((as      ));
      LEAVE();
      waitready();
      for (int i = 0; i < (SECTORSIZE/PAGESIZE); i++) {
        int ap = (as + (i*PAGESIZE));
        char* bufinpage = (bufin + (i*PAGESIZE));
        fprintf(stderr, "programming page: 0x%08X\n", ap);
        writeenable();
        ENTER();
        TX(0x02);
        TX((ap >> 16));
        TX((ap >>  8));
        TX((ap      ));
        assure((FastWrite(frob, bufinpage, PAGESIZE) == MPSSE_OK));
        LEAVE();
        waitready();
        fprintf(stderr, "verifying page: 0x%08X\n", ap);
        char bufropage[PAGESIZE];
        ENTER();
        TX(0x03);
        TX((ap >> 16));
        TX((ap >>  8));
        TX((ap      ));
        assure((FastRead(frob, bufropage, PAGESIZE) == MPSSE_OK));
        LEAVE();
        for (int k = 0; k < PAGESIZE; k++) {
          if (bufropage[k] != bufinpage[k]) {
            fprintf(stderr, "error at byte %d, retrying\n", k);
            goto retrysectornf;
          }
        }
      }
    }
    fclose(f);
  } else if (strcmp(cmd, "flashrobust") == 0) {
    FILE *const f = fopen("inp.bin", "rb");
    assure((f != NULL));
    assure((CHIPSIZE == ((CHIPSIZE/PAGESIZE)*PAGESIZE)));
    int const SECTORSIZE = 4096;
    assure((CHIPSIZE == ((CHIPSIZE/SECTORSIZE)*SECTORSIZE)));
    char* image = malloc(CHIPSIZE);
    assure((fread(image, CHIPSIZE, 1, f) == 1));
    flash_robust(PAGESIZE, SECTORSIZE, CHIPSIZE, image);
  } else if (strcmp(cmd, "mxrdid") == 0) {
    ENTER();
    TX(0x9F);
    int i1 = RXIU();
    int i2 = RXIU();
    int i3 = RXIU();
    LEAVE();
    fprintf(stderr, "rdid: [1]=%d [2]=%d [3]=%d\n", i1, i2, i3);
  } else if (strcmp(cmd, "mxrdidloop") == 0) {
    for (int i = 0 ;; i++) {
      ENTER();
      TX(0x9F);
      int i1 = RXIU();
      int i2 = RXIU();
      int i3 = RXIU();
      LEAVE();
      if (!((i1 == 200) && (i2 == 64) && (i3 == 22))) {
        fprintf(stderr, "%d: [1]=%d [2]=%d [3]=%d\n", i, i1, i2, i3);
      }
    }
  } else {
    fprintf(stderr, "command not recognized\n");
    assure(0);
  }
  
  return 0;
}
