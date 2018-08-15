/*
  gptize
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

#define PV LB_PV

/*
  enter adapted CRC code
*/

/*
  from: "http://home.thep.lu.se/~bjorn/crc/" https://web.archive.org/web/20171002164047/http://home.thep.lu.se/~bjorn/crc/
*/

/* Simple public domain implementation of the standard CRC32 checksum.
 * Outputs the checksum for each file given as a command line argument.
 * Invalid file names and files that cause errors are silently skipped.
 * The program reads from stdin if it is called with no arguments. */

static uint32_t crc32_for_byte(uintptr_t r)
{
  for (uintptr_t j = 0; j < 8; j++) {
    r = (((r & 1) ? 0 : ((uint32_t)(0xEDB88320))) ^ (r >> 1));
  }
  
  return ((uint32_t)(r ^ ((uint32_t)(0xFF000000))));
}

static uint32_t crc32(const uint8_t* data, uintptr_t n_bytes)
{
  uint32_t table[0x100];
  
  for (uintptr_t i = 0; i < 0x100; i++) {
    table[i] = crc32_for_byte(i);
  }
  
  uint32_t crc = 0;
  
  for (uintptr_t i = 0; i < n_bytes; i++) {
    crc = (table[((uint8_t)(crc ^ (*(data++))))] ^ (crc >> 8));
  }
  
  return crc;
}

/*
  leave adapted CRC code
*/

static void read_fully_fd(uintptr_t fd, uint8_t* buf, uintptr_t len)
{
  uint8_t const* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_read(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}

static void write_fully_fd(uintptr_t fd, uint8_t const* buf, uintptr_t len)
{
  uint8_t const* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_write(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}

#define PK __attribute__((packed))

LB_MAIN_SPEC
{
#define MOREARGS ({                                                     \
      LB_ASSURE(argc > 0);                                              \
      argc;                                                             \
    })
  
#define CONSUME ({                                                      \
      MOREARGS;                                                         \
      argc--;                                                           \
      *(argv++);                                                        \
    })
  
  CONSUME;
  
  uint64_t disk_size = lb_atou_64(CONSUME);
  LB_ASSURE(disk_size >= (2*1024*1024));
  
  uint64_t disk_size_blocks = lb_misc_div_64_by_32_exact(disk_size, 512);
  
  union PK {
    uint8_t uc[0];
    
    struct PK {
      union PK {
        uint8_t uc[512];
        
        struct PK {
          uint64_t sig; // signature/magic
          uint32_t rev; // revision
          uint32_t hrz; // header size
          uint32_t hrc; // header checksum (crc32/zlib)
          uint32_t rsv; // reserved
          uint64_t lba; // lba of current header
          uint64_t lbb; // lba of other header
          uint64_t lbf; // lba first usable
          uint64_t lbl; // lba last usable
          uint8_t  gid[16]; // disk guid
          uint64_t lbp; // lba of partition entries associated with this header copy
          uint32_t pan; // number of partitions in partition array
          uint32_t pez; // size of a partition entry
          uint32_t pac; // partition array checksum (crc32/zlib)
        } id;
      } hdr;
      
      union PK {
        uint8_t uc[0];
        
        struct PK {
          union PK {
            uint8_t uc[128];
            
            struct PK {
              uint8_t unk[0];
            } id;
          } pai[128];
        } id;
      } paa;
    } id;
  } gpt;
  
  LB_ASSURE((sizeof(gpt) == (33*512)));
  
  // read gpt
  {
    read_fully_fd(0, (gpt.uc), sizeof(gpt));
  }
  
  // check constants
  LB_ASSURE((gpt.id.hdr.id.sig == ((uint64_t)(0x5452415020494645))));
  LB_ASSURE((gpt.id.hdr.id.rev == ((uint32_t)(0x00010000))));
  LB_ASSURE((gpt.id.hdr.id.hrz == 92));
  LB_ASSURE((gpt.id.hdr.id.rsv == 0));
  LB_ASSURE((gpt.id.hdr.id.lba == (disk_size_blocks - 1)));
  LB_ASSURE((gpt.id.hdr.id.lbb == 1));
  LB_ASSURE((gpt.id.hdr.id.lbf == 34));
  LB_ASSURE((gpt.id.hdr.id.lbl == (disk_size_blocks - 33 - 1)));
  LB_ASSURE((gpt.id.hdr.id.lbp == (disk_size_blocks - 33)));
  LB_ASSURE((gpt.id.hdr.id.pan == 128));
  LB_ASSURE((gpt.id.hdr.id.pez == 128));
  
  // check slack
  {
    for (uintptr_t i = sizeof(gpt.id.hdr.id); i < sizeof(gpt.id.hdr); i++) {
      LB_ASSURE_EQZ(gpt.id.hdr.uc[i]);
    }
  }
  
  // check pac
  {
    LB_ASSURE(crc32(gpt.id.paa.uc, sizeof(gpt.id.paa)) == gpt.id.hdr.id.pac);
  }
  
  uint32_t hrc_gen(void)
  {
    gpt.id.hdr.id.hrc = 0;
    
    return crc32(gpt.id.hdr.uc, gpt.id.hdr.id.hrz);
  }
  
  // check hrc
  {
    LB_ASSURE(({ uint32_t tmp = gpt.id.hdr.id.hrc; (hrc_gen() == tmp); }));
  }
  
  // relocate gpt to first sector
  {
    gpt.id.hdr.id.lba = 1;
    gpt.id.hdr.id.lbb = (disk_size_blocks - 1);
    gpt.id.hdr.id.lbp = 2;
    gpt.id.hdr.id.hrc = hrc_gen();
  }
  
  // write mbr
  {
    union PK {
      uint8_t uc[0];
      
      struct PK {
        uint8_t boot[446];
        
        union PK {
          uint8_t uc[0];

          struct PK {
            uint8_t  sta; // status
            uint8_t  chf[3];
            uint8_t  ptt; // partition type code
            uint8_t  chl[3];
            uint32_t lbf;
            uint32_t lbz;
          } id;
        } paa[4];
        
        uint16_t sig;
      } id;
    } mbr;
    
    LB_ASSURE((sizeof(mbr) == 512));
    
    LB_BZERO(mbr);
    
    mbr.id.paa[0].id.chf[1] = ((uint8_t)(0x20));
    mbr.id.paa[0].id.ptt    = ((uint8_t)(0xEE));
    mbr.id.paa[0].id.chl[0] = ((uint8_t)(0xFF));
    mbr.id.paa[0].id.chl[1] = ((uint8_t)(0xFF));
    mbr.id.paa[0].id.chl[2] = ((uint8_t)(0xFF));
    mbr.id.paa[0].id.lbf = 1;
    mbr.id.paa[0].id.lbz = ({ uint64_t lbz = (disk_size_blocks - 1); (((lbz & ((uint32_t)(-1))) == lbz) ? ((uint32_t)(lbz)) : ((uint32_t)(-1))); });
    mbr.id.paa[0].id.lbz = ((uint32_t)(-1));
    
    mbr.id.sig = ((uint16_t)(0xAA55));
    
    write_fully_fd(1, (mbr.uc), sizeof(mbr));
  }
  
  // write gpt
  {
    write_fully_fd(1, (gpt.uc), sizeof(gpt));
  }

  // success
  {
    lbt_exit_group(0);
  }
}
