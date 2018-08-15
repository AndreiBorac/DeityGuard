/*
  murmur - calculate murmur checksum of a file
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

#define TR LB_TR
#define PV LB_PV
#define AV LB_AV
#define DG LB_DG

static void read_fully_fd(uintptr_t fd, uint8_t* buf, uintptr_t len)
{
  uint8_t const* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_read(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}
// "copyright" notice preserved for below 2 functions adapted from https://github.com/yonik/java_util/blob/master/src/util/hash/MurmurHash3.java
/**
 *  The MurmurHash3 algorithm was created by Austin Appleby and placed in the public domain.
 *  This java port was authored by Yonik Seeley and also placed into the public domain.
 *  The author hereby disclaims copyright to this source code.
 *  <p>
 *  This produces exactly the same hash values as the final C++
 *  version of MurmurHash3 and is thus suitable for producing the same hash values across
 *  platforms.
 *  <p>
 *  The 32 bit x86 version of this hash should be the fastest variant for relatively short keys like ids.
 *  murmurhash3_x64_128 is a good choice for longer strings or if you need more than 32 bits of hash.
 *  <p>
 *  Note - The x86 and x64 versions do _not_ produce the same results, as the
 *  algorithms are optimized for their respective platforms.
 *  <p>
 *  See http://github.com/yonik/java_util for future updates to this file.
 */
static uint32_t murmur3_32_0(uint32_t const* key_x4, uintptr_t len, uint32_t h)
{
  uint32_t const c1 = 0xcc9e2d51;
  uint32_t const c2 = 0x1b873593;
  uint32_t const c3 = 0xe6546b64;
  
  uintptr_t i = (len >> 2);
  
  while (i--) {
    uint32_t k = (*(key_x4++));
    k *= c1;
    k = (k << 15) | (k >> 17);
    k *= c2;
    h ^= k;
    h = (h << 13) | (h >> 19);
    h = (h * 5) + c3;
  }
  
  return h;
}

static uint32_t murmur3_32_f(uint32_t h, uintptr_t len)
{
  uint32_t const c4 = 0x85ebca6b;
  uint32_t const c5 = 0xc2b2ae35;
  
  h ^= ((uint32_t)(len));
  
  h ^= h >> 16;
  h *= c4;
  h ^= h >> 13;
  h *= c5;
  h ^= h >> 16;
  
  return h;
}

LB_MAIN_SPEC
{
  LB_ASSURE((argc == 3));
  
  {
    uintptr_t sz_initial = lb_misc_narrow_64_ptr(lb_atou_64(argv[1]));
    
    LB_ASSURE((sz_initial & 3) == 0);
    
    char const* fn = argv[2];
    uintptr_t   fd = LBT_OK(lbt_open(fn, lbt_O_RDONLY, 0));
    
    uint32_t value = 0;
    
    uint8_t buf[65536];
    
    void consume(uintptr_t amt)
    {
      read_fully_fd(fd, buf, amt);
      value = murmur3_32_0(((uint32_t const*)(buf)), amt, value);
    }
    
    {
      uintptr_t sz = sz_initial;
      
      while (sz > sizeof(buf)) {
        consume(sizeof(buf));
        sz -= sizeof(buf);
      }
      
      if (sz > 0) {
        consume(sz);
      }
    }
    
    value = murmur3_32_f(value, sz_initial);
    
    lb_print("us", LB_U(value), "\n");
  }
  
  lbt_exit_simple(0);
  
  LB_ABORT;
}
