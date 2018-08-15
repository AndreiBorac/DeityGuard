/*
  libaboon/definitions.c
  copyright (c) 2017 by andrei borac
*/

/*
  enter definitions that are so frequently used or generic that we do
  not prefix them with lb_
*/

#define bool _Bool
#define true  ((bool)(1))
#define false ((bool)(0))

#define NULL ((void*)(0))

#ifndef LB_DEFINITIONS_NO_INT_T

typedef /*    */ char   int8_t;
typedef unsigned char  uint8_t;
typedef /*    */ short  int16_t;
typedef unsigned short uint16_t;
typedef /*    */ int    int32_t;
typedef unsigned int   uint32_t;

#ifdef LB_ARCH_X86_64
#ifndef LB_ARCH_ANY_64
#define LB_ARCH_ANY_64
#define LB_ARCH_HAS_DIV_64
#endif
typedef /*    */ long  int64_t;
typedef unsigned long uint64_t;
typedef /*    */ long  intptr_t;
typedef unsigned long uintptr_t;
#endif

#ifdef LB_ARCH_ARM_32
#ifndef LB_ARCH_ANY_32
#define LB_ARCH_ANY_32
#endif
typedef /*    */ long long  int64_t;
typedef unsigned long long uint64_t;
typedef /*    */ int  intptr_t;
typedef unsigned int uintptr_t;
#endif

#endif

/*
  leave unprefixed definitions
*/

#define LB_LF "\n"

#define LB_UNUSED __attribute__((__unused__))
#define LB_PACKED __attribute__((__packed__))
#define LB_INLINE inline __attribute__((__always_inline__))
#define LB_NO_INLINE __attribute__((noinline))

#define LBI_VA_NARGS_(_1, _2, _3, _4, _5, _6, _7, _8, _9, N, ...) N
#define LB_VA_NARGS(...) LBI_VA_NARGS_(__VA_ARGS__, 9, 8, 7, 6, 5, 4, 3, 2, 1)
#define LBI_VA_NARGS_CALL__(f, c, ...) f##c(__VA_ARGS__)
#define LBI_VA_NARGS_CALL_(f, c, ...) LBI_VA_NARGS_CALL__(f, c, __VA_ARGS__)
#define LB_VA_NARGS_CALL(f, ...) LBI_VA_NARGS_CALL_(f, LB_VA_NARGS(__VA_ARGS__), __VA_ARGS__)

//#define LB_USE_VALUE(x) ({ __typeof__(x) LB_USE_VALUE__A = (x); })

#define LB_TYPEDECL(x) struct struct_##x; typedef struct struct_##x x;
#define LB_TYPEDEFN(x) struct struct_##x
#define LB_TYPEBOTH(x) LB_TYPEDECL(x) LB_TYPEDEFN(x)

#define LB_CHECK_TYPE(t, x) ({                                          \
      ((void)("LB_CHECK_TYPE"));                                        \
      t LB_CHECK_TYPE__A;                                               \
      __typeof__(x) LB_CHECK_TYPE__B;                                   \
      ((void)((&LB_CHECK_TYPE__A) == (&LB_CHECK_TYPE__B)));             \
      (x);                                                              \
    })

#define LB_CHECK_IS_PTR(x) ({                                           \
      ((void)("LB_CHECK_IS_PTR"));                                      \
      void const* LB_CHECK_IS_PTR__A LB_UNUSED = (x);                   \
      ((__typeof__(x))(LB_CHECK_IS_PTR__A));                            \
    })

#define LB_I(x) (( intptr_t)(x))
#define LB_U(x) ((uintptr_t)(x))

#define LB_IU(x) ({ ((void)("LB_IU")); LB_I(LB_CHECK_TYPE(uintptr_t, (x))); })
#define LB_UI(x) ({ ((void)("LB_UI")); LB_U(LB_CHECK_TYPE( intptr_t, (x))); })

#ifdef LB_ARCH_X86_64

__asm__
(
  "lbi_launder_asm:" LB_LF
  "retq" LB_LF
);

#endif

#ifdef LB_ARCH_ARM_32

__asm__
(
  "lbi_launder_asm:" LB_LF
  "mov pc, lr" LB_LF
);

#endif

/*
  used to prevent the compiler from performing further constant
  propagation of val.
*/
extern uintptr_t lb_launder(uintptr_t val) __asm__("lbi_launder_asm");

#ifdef LB_ARCH_X86_64

__asm__
(
  ".globl lbi_breakpoint_asm" LB_LF
  "lbi_breakpoint_asm:" LB_LF
  "retq" LB_LF
);

#endif

#ifdef LB_ARCH_ARM_32

__asm__
(
  ".globl lbi_breakpoint_asm" LB_LF
  "lbi_breakpoint_asm:" LB_LF
  "mov pc, lr" LB_LF
);

#endif

extern void lb_breakpoint(uintptr_t val) __asm__("lbi_breakpoint_asm");

#define LB_B(x) (lb_breakpoint(x))

#define LB_BR_U(x) ({ ((void)("LB_BR_U")); uintptr_t LB_BR_U__A = (x); lb_breakpoint(LB_BR_U__A); })
#define LB_BR_V(x) ({ ((void)("LB_BR_V")); LB_BR_U(LB_CHECK_IS_PTR(x)); })

#define LB_PTRADD(x, a) ({ ((void)("LB_PTRADD")); ((__typeof__(x))((LB_U(LB_CHECK_IS_PTR(x))) + a)); })
#define LB_PTRDIF(x, y) ({ ((void)("LB_PTRDIF")); LB_CHECK_IS_PTR(x); LB_CHECK_IS_PTR(y); LB_U(x) - LB_U(y); })

#define LB_COMPILER_BARRIER __asm__ __volatile__ ("" ::: "memory")

#define LB_ARRLEN(x) ((sizeof((x)))/(sizeof((x)[0])))

#define LB_CAST_ASGN(x, y) ({ x = ((__typeof__(x))(y)); })
#define LB_CLONE(x, y) __typeof__(&(y)) x = (&(y));

#define LB_MIN(x, y) ({                                                 \
      __typeof__(x)         LB_MIN__A = (x);                            \
      __typeof__(y)         LB_MIN__B = (y);                            \
      __typeof__(((x)+(y))) LB_MIN__C;                                  \
                                                                        \
      if (LB_MIN__A < LB_MIN__B) { LB_MIN__C = LB_MIN__A; } else { LB_MIN__C = LB_MIN__B; }; \
                                                                        \
      LB_MIN__C;                                                        \
    })

#define LB_MAX(x, y) ({                                                 \
      __typeof__(x)         LB_MIN__A = (x);                            \
      __typeof__(y)         LB_MIN__B = (y);                            \
      __typeof__(((x)+(y))) LB_MIN_C;                                   \
                                                                        \
      if (LB_MIN__A > LB_MIN__B) { LB_MIN__C = LB_MIN__A; } else { LB_MIN__C = LB_MIN__B; }; \
                                                                        \
      LB_MIN__C;                                                        \
    })
