/*
  unpranker - an inputless unpacker
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

#define HEADER "H578OhBMuIxJR80C"

#define STRLEN(x) ({ static const char __strlen[] = (x ""); (sizeof(__strlen) - 1); })

#define TR LB_TR
#define PV LB_PV
#define AV LB_AV
#define DG LB_DG

#define _STDBOOL_H
#define _STDDEF_H
#define _STDINT_H
#define _STDIO_H
#define _STDLIB_H
#define _STRING_H

#define size_t uintptr_t

#define XZ_DEC_SINGLE

static void* provided_memcpy(void* dst, const void* src, size_t siz)
{
  lb_memcpy(dst, src, siz);
  return dst;
}

static void* provided_memset(void* dst, int val, size_t siz)
{
  LB_ASSURE_EQZ(val);
  lb_bzero(dst, siz);
  return dst;
}

static void* provided_memmove(void* dst, void const* src, size_t n)
{
  // meh, libaboon memcpy currently handles overlapped regions, though that is not guaranteed
  lb_memcpy(dst, src, n);
  return dst;
}

typedef struct {
  lb_sbrk_t* sb;
}
g_t;

g_t g;

static void* provided_malloc(size_t size)
{
  return lb_sbrk(g.sb, size);
}

static void provided_free(void* vptr LB_UNUSED)
{
}

static int provided_memcmp(const void* s1, void const* s2, size_t n)
{
  if (lb_memcmp(s1, s2, n)) {
    return 0;
  } else {
    return -1;
  }
}

#define memcpy  provided_memcpy
#define memset  provided_memset
#define memmove provided_memmove
#define malloc  provided_malloc
#define free    provided_free
#define memcmp  provided_memcmp

#pragma GCC diagnostic push

#pragma GCC diagnostic ignored "-Wc++-compat"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Wswitch-default"
#pragma GCC diagnostic ignored "-Winline"

#include "xz-embedded/xz_crc32.c"
//#include "xz-embedded/xz_crc64.c"
//#include "xz-embedded/xz_dec_bcj.c"
#include "xz-embedded/xz_dec_lzma2.c"
#include "xz-embedded/xz_dec_stream.c"

#pragma GCC diagnostic pop

static void write_fully_fd(uintptr_t fd, uint8_t const* buf, uintptr_t len)
{
  uint8_t const* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_write(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}

static char const* locate(char const* start)
{
  DG("sus", "start=", LB_U(start), "\n");
  
  while (true) {
    DG("s", "start...\n");
    start  = ((char const*)(lb_memmem(start, (1<<30), HEADER, STRLEN(HEADER))));
    DG("sus", "start=", LB_U(start), " [?]\n");
    start += STRLEN(HEADER);
    
    if ((*(start++)) == ';') {
      break;
    }
  }
  
  DG("sus", "start=", LB_U(start), "\n");
  
  return start;
}

static uintptr_t atou(char const** archive)
{
  uintptr_t x = 0;
  
  char c;
  
  while (((c = (*((*archive)++))) != ';')) {
    LB_ASSURE((('0' <= c) && (c <= '9')));
    x = ((x << 3) + (x << 1));
    x += LB_U(c - '0');
  }
  
  return x;
}

static char const* handle_inner_stream(char const* x, char const* const* argv LB_UNUSED, char const* const* envp)
{
  DG("sus", "handle_inner_stream(x=", LB_U(x), ", ...)\n");
  
  while (true) {
    bool executable = false;
    
    char x0;
    
    switch ((x0 = (*(x++)))) {
    case '0': /* nop */
      {
        DG("s", "unpranker: nop\n");
        
        break;
      }
      
    case 'R': /* return */
      {
        DG("s", "unpranker: return\n");
        
        return x;
      }
      
    case 'E': /* exit */
      {
        DG("s", "unpranker: exit\n");
        
        lbt_exit_simple(0);
        
        LB_ILLEGAL;
      }
      
    case 'X': /* execve */
      {
        char const* s = x; x += (lb_strlen(s) + 1);
        
        DG("sss", "unpranker: execve '", s, "'\n");
        
        char const* argv_pass[] = { s, NULL };
        lbt_execve_bypass(s, argv_pass, envp);
        
        LB_ILLEGAL;
      }
      
    case 'd': /* mkdir */
      {
        char const* s = x; x += (lb_strlen(s) + 1);
        
        DG("sus", "lb_strlen(s)=", lb_strlen(s), "\n");
        DG("sss", "unpranker: mkdir '", s, "'\n");
        
        lbt_mkdir_bypass(s, 0700);
        
        break;
      }
      
    case 'u': /* unlink */
      {
        char const* s = x; x += (lb_strlen(s) + 1);
        
        DG("sss", "unpranker: unlink '", s, "'\n");
        
        lbt_unlink(s);
        
        break;
      }
      
    case 'h': /* symlink */
      {
        char const* s = x; x += (lb_strlen(s) + 1);
        char const* t = x; x += (lb_strlen(t) + 1);
        
        DG("sssss", "unpranker: symlink '", s, "' to '", t, "'\n");
        
        lbt_symlink_bypass(t, s);
        
        break;
      }
      
    case 'x': /* executable file */
      executable = true;
      /*
        note that the executable property as implemented here only
        affects newly created files, as O_TRUNC preserves permissions
        on existing files. we do not explicitly chmod. use the unlink
        feature to reset permissions.
      */
      /*
        fall through.
      */
    case 'f': /* file */
      {
        char const* s = x; x += (lb_strlen(s) + 1);
        char const* l = x; x += (lb_strlen(l) + 1);
        
        uintptr_t len = lb_misc_narrow_64_ptr(lb_atou_64(l));
        
        DG("sssus", "unpranker: file '", s, "' [", len, "]\n");
        
        uintptr_t fd = LBT_OK(lbt_open(s, (lbt_O_CREAT | lbt_O_TRUNC | lbt_O_WRONLY), (executable ? 0700 : 0600)));
        
        write_fully_fd(fd, ((uint8_t const*)(x)), len); x += len;
        
        LBT_OK(lbt_close(fd));
        
        break;
      }
      
    default:
      {
        DG("sus", "unpranker: illegal token: ", LB_U(x0), "\n");
        
        LB_ILLEGAL;
      }
    }
  }
}

static char const* handle_segment(char const* archive, char const* const* argv, char const* const* envp)
{
  DG("sus", "handle_segment(archive=", LB_U(archive), ", ...)\n");
  
  // read mode
  uintptr_t mode = atou((&(archive)));
  
  switch (mode) {
  case 2595: /* uncompressed magic */
    {
      archive = handle_inner_stream(archive, argv, envp);
      
      break;
    }
    
  case 5786: /* xz compressed magic */
    {
      // read sizes (id = uncompressed, xz = compressed)
      uintptr_t sz_id = atou((&(archive)));
      uintptr_t sz_xz = atou((&(archive)));
      
      DG("sus", "sz_id=", sz_id, "\n");
      DG("sus", "sz_xz=", sz_xz, "\n");
      
      // allocate working memory
      char* working = ((char*)(lb_sbrk(g.sb, sz_id)));
      
      PV(working);
      
      // decompress
      {
        xz_crc32_init();
        struct xz_dec* dec = xz_dec_init(XZ_SINGLE, 0);
        LB_ASSURE(dec);
        struct xz_buf buf = { .in = ((uint8_t*)(archive)), 0, sz_xz, ((uint8_t*)(working)), 0, sz_id };
        {
          enum xz_ret reason;
          
          if ((reason = (xz_dec_run(dec, (&buf)))) != XZ_STREAM_END) {
            DG("sus", "xz_dec_run failed, reason ", reason, "\n");
            
            LB_ILLEGAL;
          }
        }
      }
      
      handle_inner_stream(working, argv, envp);
      
      archive += sz_xz;
      
      break;
    }
    
  default:
    {
      LB_ILLEGAL;
    }
  }
  
  DG("sus", "handle_segment (out) archive=", LB_U(archive), "\n");
  
  return archive;
}

LB_MAIN_SPEC
{
  lb_sbrk_t sb_;
  g.sb = (&(sb_));
  lb_sbrk_initialize(g.sb);
  
  {
#define PGSZ 4096
    
    char* bas = ((char*)(lb_sbrk(g.sb, PGSZ)));
    char* lim = bas;
    char* end = (lim + PGSZ);
    
    {
      uintptr_t fd = LBT_OK(lbt_open(argv[0], lbt_O_RDONLY, 0));
      
      while (true) {
        if (lim == end) {
          LB_ASSURE(lb_sbrk(g.sb, PGSZ) == end);
          end += PGSZ;
        }
        
        intptr_t amt = lbt_read(fd, lim, LB_PTRDIF(end, lim));
        
        LB_ASSURE_GEZ(amt);
        
        if (amt == 0) break;
        
        lim += amt;
      }
    }
    
    char const* archive = locate(((char const*)(bas)));
    
    DG("sus", "main: archive=", LB_U(archive), "\n");
    
    while (true) {
      archive = handle_segment(archive, argv, envp);
    }
  }
  
  LB_ABORT;
}
