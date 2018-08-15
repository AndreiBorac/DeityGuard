/*
  libaboon/sha256.c
  copyright (c) 2017 by andrei borac
*/

/*
  sha256 state size in 8-bit bytes.
*/
enum { lb_sha256_staz08 = 32, };

/*
  sha256 state size in 32-bit words.
*/
enum { lb_sha256_staz32 =  8, };

/*
  sha256 block size in 8-bit bytes.
*/
enum { lb_sha256_blkz08 = 64, };

/*
  sha256 block size in 32-bit words.
*/
enum { lb_sha256_blkz32 = 16, };

/*
  sha256 look-up table constants size in 32-bit words.
*/
enum { lb_sha256_latz32 = 64, };

typedef struct
{
  uint32_t vector[lb_sha256_staz32];
}
lb_sha256_state_t;

typedef struct
{
  uint32_t values[lb_sha256_blkz32];
}
lb_sha256_block_t;

static uint32_t const lb_sha256_cons32[lb_sha256_latz32] =
  {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  };

static LB_INLINE uint32_t lb_sha256_rrot32(uint32_t x, uintptr_t p)
{
  return ((x >> p) | (x << (32 - p)));
}

/*
  sets /state to the SHA-256 initialization vector.
*/
static void lb_sha256_init(lb_sha256_state_t* state)
{
  state->vector[0] = 0x6a09e667;
  state->vector[1] = 0xbb67ae85;
  state->vector[2] = 0x3c6ef372;
  state->vector[3] = 0xa54ff53a;
  state->vector[4] = 0x510e527f;
  state->vector[5] = 0x9b05688c;
  state->vector[6] = 0x1f83d9ab;
  state->vector[7] = 0x5be0cd19;
}

/*
  copies util_uint32 values from one memory range to another.
*/
static LB_INLINE void lb_sha256_util_mov32(uint32_t* dst, uint32_t const* src, uint32_t* lim)
{
  while (src < lim) {
    *(dst++) = *(src++);
  }
}

/*
  /public. updates /state to reflect the processing of /blkc groups
  of /sha256_blkz32 values of type uint32_t, starting at /base.
  
  /swap should be set to true if the input integers are in not in
  host-endian format (i.e., they need to be "byte-swapped" before
  performing the SHA calculations).
*/
static void lb_sha256_core(lb_sha256_state_t* state, uint32_t* base, uintptr_t blkc, bool swap)
{
  //fpaste_stderr("sms", "sha256_core: ", base, (blkc * sizeof(sha256_block)), "\n");
  
  uint32_t w[lb_sha256_latz32];
  
  uint32_t a = state->vector[0];
  uint32_t b = state->vector[1];
  uint32_t c = state->vector[2];
  uint32_t d = state->vector[3];
  uint32_t e = state->vector[4];
  uint32_t f = state->vector[5];
  uint32_t g = state->vector[6];
  uint32_t h = state->vector[7];
  
  while (blkc--) {
    if (swap) {
      //for (uintptr_t i = 0; i < lb_sha256_blkz32; i++) {
      lb_bswap_32_a(w, base, lb_sha256_blkz32);
      //}
    } else {
      lb_sha256_util_mov32(w, base, (base + lb_sha256_blkz32));
    }
    
    base += lb_sha256_blkz32;
    
    // having pulled a block into w[], now do sha256 ...
    
    for (uintptr_t i = lb_sha256_blkz32; i < lb_sha256_latz32; i++) {
      uint32_t c0 = w[i-15];
      uint32_t c1 = w[i-2];
      uint32_t s0 = (lb_sha256_rrot32(c0,  7) ^ lb_sha256_rrot32(c0, 18) ^ (c0 >>  3));
      uint32_t s1 = (lb_sha256_rrot32(c1, 17) ^ lb_sha256_rrot32(c1, 19) ^ (c1 >> 10));
      w[i] = (w[i-16] + s0 + w[i-7] + s1);
    }
    
    for (uintptr_t i = 0; i < lb_sha256_latz32; i++) {
      uint32_t Ra = (lb_sha256_rrot32(a, 2) ^ lb_sha256_rrot32(a, 13) ^ lb_sha256_rrot32(a, 22));
      uint32_t Re = (lb_sha256_rrot32(e, 6) ^ lb_sha256_rrot32(e, 11) ^ lb_sha256_rrot32(e, 25));
      uint32_t ac = ((a & b) ^ (a & c) ^ (b & c));
      uint32_t eg = ((e & f) ^ ((~e) & g));
      uint32_t t1 = (Re + eg + h + lb_sha256_cons32[i] + w[i]);
      uint32_t t2 = (Ra + ac);
      
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
    }
    
    state->vector[0] = (a += state->vector[0]);
    state->vector[1] = (b += state->vector[1]);
    state->vector[2] = (c += state->vector[2]);
    state->vector[3] = (d += state->vector[3]);
    state->vector[4] = (e += state->vector[4]);
    state->vector[5] = (f += state->vector[5]);
    state->vector[6] = (g += state->vector[6]);
    state->vector[7] = (h += state->vector[7]);
  }
}

/*
  /public. updates /state to reflect the processing of bytes /off
  (inclusive) through /lim (exclusive), and increments /total by /size
  if /total is non-NULL. if /fini is non-zero, finalization is
  applied. set /fini to 1 to get the SHA standard padding. set /fini
  to 2 to get non-standard integer-based padding. requires that either
  /size be a multiple of the block size, or that /fini is true. /total
  may be NULL for all-at-once operation.
  
  /swap should be set as for /sha256_core. note that if /fini is 1,
  the finalization sequence is always appended bytewise in the
  standard big-endian form before the effect of /swap. therefore,
  using /fini 1 without /swap on a little-endian host will not produce
  the same effect as /fini 1 with /swap on a big-endian host, even if
  the application-supplied data to be hashed is consistently in
  host-endian byte order. /fini 2 exists for this reason; it uses a
  padding scheme that is written in host endianness. for int32_t data
  in host-endian format, /fini 2 produces the same effect when used
  without /swap on a little-endian host as when used with /swap on a
  little-endian host, and it produces the same effect when used with
  /swap on a little-endian host as when used without /swap on a
  big-endian host.
*/
static void lb_sha256_calc(lb_sha256_state_t* state, uint64_t* total, uint8_t const* off, uint8_t const* lim, bool swap, int fini)
{
  uintptr_t len = LB_PTRDIF(lim, off);
  
  uint64_t total_saved;
  
  if (total != NULL) {
    total_saved = (*total += len);
  } else {
    total_saved = len;
  }
  
  /*
    handle all whole blocks
  */
  {
    uintptr_t num = (len / sizeof(lb_sha256_block_t));
    
    uint32_t values[lb_sha256_blkz32];
    
    while (num--) {
      lb_memcpy(values, off, sizeof(values));
      off += sizeof(values);
      
      lb_sha256_core(state, values, 1, swap);
    }
    
    len = LB_PTRDIF(lim, off);
  }
  
  /*
    handle partial block and finalization
  */
  {
//#if 0
    if (fini == 0) {
      LB_ASSURE((off == lim));
    } else {
//#endif
      total_saved <<= 3; // careful! data is a series of bits, not bytes!
      
      union {
        uint8_t  u1[(2 * lb_sha256_blkz32 * sizeof(uint32_t))];
        uint32_t u4[(2 * lb_sha256_blkz32                   )];
        uint64_t u8[(    lb_sha256_blkz32                   )];
      } blocks;
      
      LB_BZERO(blocks);
      
      lb_memcpy(blocks.u1, off, len);
      
//#if 0
      /****/ if (fini == 1) {
//#endif
        blocks.u1[len++] = 0x80;
        len += 8;
        len = ((len + (lb_sha256_blkz08 - 1)) & (LB_U(~(lb_sha256_blkz08 - 1))));
        len -= 8;
        blocks.u1[len++] = ((uint8_t)(total_saved >> 56));
        blocks.u1[len++] = ((uint8_t)(total_saved >> 48));
        blocks.u1[len++] = ((uint8_t)(total_saved >> 40));
        blocks.u1[len++] = ((uint8_t)(total_saved >> 32));
        blocks.u1[len++] = ((uint8_t)(total_saved >> 24));
        blocks.u1[len++] = ((uint8_t)(total_saved >> 16));
        blocks.u1[len++] = ((uint8_t)(total_saved >>  8));
        blocks.u1[len++] = ((uint8_t)(total_saved      ));
//#if 0
      } else if (fini == 2) {
        len += 8;
        len = ((len + (lb_sha256_blkz08 - 1)) & (LB_U(~(lb_sha256_blkz08 - 1))));
        len -= 8;
        blocks.u4[len >> 2] = ((uint32_t)(total_saved >> 32));
        len += 4;
        blocks.u4[len >> 2] = ((uint32_t)(total_saved      ));
        len += 4;
      } else {
        LB_ASSURE((fini == 1) || (fini == 2));
        LB_ILLEGAL;
        while (1);
      }
//#endif
      
      LB_COMPILER_BARRIER;
      
      if (len <= sizeof(lb_sha256_block_t)) {
        // sans overflow block
        lb_sha256_core(state, blocks.u4, 1, swap);
      } else {
        // avec overflow block
        lb_sha256_core(state, blocks.u4, 2, swap);
      }
//#if 0
    }
//#endif
  }
}

static LB_INLINE void lb_sha256_calc_len(lb_sha256_state_t* state, uint64_t* total, uint8_t const* off, uintptr_t len, bool swap, int fini)
{
  return lb_sha256_calc(state, total, off, (off + len), swap, fini);
}

/*
  sha256 display string length.
*/
enum { lb_sha256_dsiz = 64, };

static uintptr_t lb_sha256_dump(lb_sha256_state_t const* state, char* out)
{
  static char const nib2hex[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
  
  for (uintptr_t i = 0; i < 8; i++) {
    for (uintptr_t j = 0; j < 8; j++) {
      *(out++) = nib2hex[((state->vector[i] >> ((8-1-j) << 2)) & 0x0F)];
    }
  }
  
  *out = '\0';
  
  return lb_sha256_dsiz;
}
