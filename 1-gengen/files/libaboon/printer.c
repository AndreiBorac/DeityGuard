/*
  libaboon/printer.c
  copyright (c) 2017 by andrei borac
*/

#ifndef LB_STDIO_STDERR
#define LB_STDIO_STDERR 2
#endif

#ifdef LB_ARCH_X86_64
#define LBI_PRINT_S_INNER_PAR uintptr_t a LB_UNUSED, uintptr_t b LB_UNUSED, uintptr_t c LB_UNUSED, uintptr_t d LB_UNUSED, uintptr_t e LB_UNUSED
#endif

#ifdef LB_ARCH_ARM_32
#define LBI_PRINT_S_INNER_PAR uintptr_t a LB_UNUSED, uintptr_t b LB_UNUSED, uintptr_t c LB_UNUSED
#endif

#define LBI_PRINT_S__TA(t, v) t v = ((t)((*(++arg))));

__attribute__((used))
static uintptr_t lbi_print_s_inner(LBI_PRINT_S_INNER_PAR, char* buf, char const* fmt, ...)
{
  char* buf_saved = buf;
  
  void const** arg = ((void const**)(&fmt));
  
  bool width_8 = false;
  
  while (*fmt) {
    switch (*fmt) {
    case ' ':
      {
        break;
      }
      
    case 's':
      {
        LBI_PRINT_S__TA(char const*, str);
        
        if (str != NULL) {
          uintptr_t len = lb_strlen(str);
          
          if (buf_saved) {
            lb_memcpy(buf, str, len);
          }
          
          buf += len;
        } else {
          if (buf_saved) {
            lb_memcpy(buf, "(null)", 6);
          }
          
          buf += 6;
        }
        
        break;
      }
      
    case 'm':
      {
        LBI_PRINT_S__TA(uint8_t const*, mem);
        LBI_PRINT_S__TA(uintptr_t, len);
        
        if (buf_saved) {
          static char const nibble_to_char[] = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
          
          for (uintptr_t i = 0; i < len; i++) {
            (*(buf++)) = nibble_to_char[(mem[i] >> 4) & 0x0F];
            (*(buf++)) = nibble_to_char[(mem[i]     ) & 0x0F];
          }
        } else {
          buf += (len << 1);
        }
        
        break;
      }
      
    case 'u':
      {
        if (width_8) {
          width_8 = false;
          
          LBI_PRINT_S__TA(uint64_t*, valptr);
          uint64_t val = *valptr;
          
          if (buf_saved) {
            buf += lb_utoa_64(buf, val);
          } else {
            buf += lb_utoa_64_sz(val);
          }
        } else {
          LBI_PRINT_S__TA(uintptr_t, val);
          
          if (buf_saved) {
            buf += lb_utoa_64(buf, val);
          } else {
            buf += lb_utoa_64_sz(val);
          }
        }
        
        break;
      }
      
    case '8':
      {
        width_8 = true;
        
        break;
      }
      
    default:
      {
        LB_ILLEGAL;
      }
    }
    
    fmt++;
  }
  
  if (buf_saved) {
    *buf = '\0';
  }
  
  return LB_PTRDIF(buf, buf_saved);
}

/*
  define this to force proper ABI use when invoking print_s, at the
  cost of an extra jump instruction (thunk)
  
  for now, just adding __attribute__((used)) to lbi_print_s_inner,
  required for the thunk to work, seems by itself to do the job of
  preventing gcc from carrying out optimizations that change the ABI
  
  so this isn't needed right now, but that could easily change
*/
//#define LBI_PRINT_S_FORCE_ABI

#ifdef LBI_PRINT_S_FORCE_ABI

#ifdef LB_ARCH_X86_64

__asm__
(
  "lbi_print_s_asm:" LB_LF
  "jmp lbi_print_s_inner" LB_LF
);

#endif

#ifdef LB_ARCH_ARM_32

__asm__
(
  "lbi_print_s_asm:" LB_LF
  "b lbi_print_s_inner" LB_LF
);

#endif

extern uintptr_t lbi_print_s(LBI_PRINT_S_INNER_PAR, char*, char const*, ...) __asm__("lbi_print_s_asm");

#else

#define lbi_print_s lbi_print_s_inner

#endif

#ifdef LB_ARCH_X86_64

#if 1

#define lb_print_s(buf, fmt, ...)                                       \
  ({                                                                    \
    uintptr_t lb_print_s__1;                                            \
    uintptr_t lb_print_s__2;                                            \
    uintptr_t lb_print_s__3;                                            \
    uintptr_t lb_print_s__4;                                            \
    uintptr_t lb_print_s__5;                                            \
    __asm__("" : "=r" (lb_print_s__1), "=r" (lb_print_s__2), "=r" (lb_print_s__3), "=r" (lb_print_s__4), "=r" (lb_print_s__5)); \
    lbi_print_s(lb_print_s__1, lb_print_s__2, lb_print_s__3, lb_print_s__4, lb_print_s__5, (buf), (fmt), ##__VA_ARGS__); \
  })

#else

#define lb_print_s(buf, fmt, ...)                                       \
  ({                                                                    \
    lbi_print_s(0, 0, 0, 0, 0, (buf), (fmt), ##__VA_ARGS__);            \
  })

#endif

#endif

#ifdef LB_ARCH_ARM_32

#if 1

#define lb_print_s(buf, fmt, ...)                                       \
  ({                                                                    \
    uintptr_t lb_print_s__1;                                            \
    uintptr_t lb_print_s__2;                                            \
    uintptr_t lb_print_s__3;                                            \
    __asm__("" : "=r" (lb_print_s__1), "=r" (lb_print_s__2), "=r" (lb_print_s__3)); \
    lbi_print_s(lb_print_s__1, lb_print_s__2, lb_print_s__3, (buf), (fmt), ##__VA_ARGS__); \
  })

#else

#define lb_print_s(buf, fmt, ...)                                       \
  ({                                                                    \
    lbi_print_s(0, 0, 0, (buf), (fmt), ##__VA_ARGS__);                  \
  })

#endif

#endif

static void lbi_print_fd(uintptr_t fd, char const* buf, uintptr_t len)
{
  while (len > 0) {
    intptr_t amt = ((intptr_t)(lb_syscall_3(lbt_SYS_write, fd, LB_U(buf), len)));
    
    if (amt <= 0) {
#ifdef LB_PRINTER_IGNORE_ERRORS
      break;
#else
      LB_ABORT;
#endif
    }
    
    uintptr_t uamt = LB_U(amt);
    
    buf += uamt;
    len -= uamt;
  }
}

#define lb_print_fd(fd, fmt, ...)                                       \
  ({                                                                    \
    char const* LB_PRINT_FD__FMT = (fmt);                               \
    uintptr_t   LB_PRINT_FD__LEN = lb_print_s(NULL, LB_PRINT_FD__FMT, ##__VA_ARGS__); \
    char        LB_PRINT_FD__BUF[LB_PRINT_FD__LEN+1];                   \
    lb_print_s(LB_PRINT_FD__BUF, LB_PRINT_FD__FMT, ##__VA_ARGS__);      \
    lbi_print_fd((fd), LB_PRINT_FD__BUF, LB_PRINT_FD__LEN);             \
    ((void)(0));                                                        \
  })

#define lb_print(fmt, ...)                                              \
  { lb_print_fd(LB_STDIO_STDERR, (fmt), ##__VA_ARGS__); }

#ifndef LB_TRACE_COND
#define LB_TRACE_COND false
#endif

#ifndef LB_BREAK_COND
#define LB_BREAK_COND false
#endif

#define LB_TR                                                           \
  {                                                                     \
    if (LB_BREAK_COND) {                                                \
      lb_breakpoint(-1U);                                               \
    }                                                                   \
                                                                        \
    if (LB_TRACE_COND) {                                                \
      lb_print("sssss", "R (", __FILE__, ")[", LBI_S__LINE__, "]\n");   \
    }                                                                   \
  }

#define LB_PV(v)                                                        \
  ({                                                                    \
    __typeof__(v) LB_PV__A = (v);                                       \
                                                                        \
    if (LB_BREAK_COND) {                                                \
      lb_breakpoint(LB_U(LB_PV__A));                                    \
    }                                                                   \
                                                                        \
    if (LB_TRACE_COND) {                                                \
      lb_print("sssusssus", "(", __FILE__, ")[", __LINE__, "]: ", #v, "=", LB_U(LB_PV__A), "\n"); \
    }                                                                   \
                                                                        \
    LB_PV__A;                                                           \
  })

#define LB_AV(v, a)                                                     \
  ({                                                                    \
    __typeof__(v) LB_AV__A = (v);                                       \
                                                                        \
    if (LB_BREAK_COND) {                                                \
      lb_breakpoint(LB_U(LB_AV__A));                                    \
    }                                                                   \
                                                                        \
    if (LB_TRACE_COND) {                                                \
      lb_print("sssusssusss", "(", __FILE__, ")[", __LINE__, "]: ", #v, "=", LB_U(LB_AV__A), " <--- ", a, "\n"); \
    }                                                                   \
                                                                        \
    LB_AV__A;                                                           \
  })

#define LB_DG(fmt, ...)                                                 \
  {                                                                     \
    if (LB_BREAK_COND) {                                                \
      lb_breakpoint(-1U);                                               \
    }                                                                   \
                                                                        \
    if (LB_TRACE_COND) {                                                \
      lb_print((fmt), ##__VA_ARGS__);                                   \
    }                                                                   \
  }

#define LB_AN(str, val)                                                 \
  ({ ((void)(str)); (val); })
