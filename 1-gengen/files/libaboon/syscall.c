/*
  libaboon/syscall.c
  copyright (c) 2017 by andrei borac
*/

#ifdef LB_ARCH_X86_64

/*
  user: %rdi, %rsi, %rdx, %rcx, %r8 and %r9
  kern: %rdi, %rsi, %rdx, %r10, %r8 and %r9
*/

__asm__
(
  "lbi_syscall_6_asm:" LB_LF
  "movq 0(%r9), %r10" LB_LF
  "movq 8(%r9), %r9" LB_LF
  "movq %rcx, %rax" LB_LF
  "syscall" LB_LF
  "retq" LB_LF
  
  "lbi_syscall_5_asm:" LB_LF
  "movq %r9, %r10" LB_LF
  "lbi_syscall_3_asm:" LB_LF
  "movq %rcx, %rax" LB_LF
  "syscall" LB_LF
  "retq" LB_LF
  
  "lbi_syscall_2_asm:" LB_LF
  "movq %rdx, %rax" LB_LF
  "syscall" LB_LF
  "retq" LB_LF
  
  "lbi_syscall_1_asm:" LB_LF
  "movq %rsi, %rax" LB_LF
  "syscall" LB_LF
  "retq" LB_LF
  
  "lbi_syscall_0_asm:" LB_LF
  "movq %rdi, %rax" LB_LF
  "syscall" LB_LF
  "retq" LB_LF
);

extern intptr_t lbi_syscall_6(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t n, uintptr_t e, uintptr_t* x) __asm__("lbi_syscall_6_asm");
extern intptr_t lbi_syscall_5(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t n, uintptr_t e, uintptr_t d)  __asm__("lbi_syscall_5_asm");
extern intptr_t lbi_syscall_3(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t n)                            __asm__("lbi_syscall_3_asm");

extern intptr_t lbi_syscall_2(uintptr_t a, uintptr_t b, uintptr_t n)                                         __asm__("lbi_syscall_2_asm");
extern intptr_t lbi_syscall_1(uintptr_t a, uintptr_t n)                                                      __asm__("lbi_syscall_1_asm");
extern intptr_t lbi_syscall_0(uintptr_t n)                                                                   __asm__("lbi_syscall_0_asm");

static intptr_t lb_syscall_6(uintptr_t n, uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e, uintptr_t f)
{
  uintptr_t x[] = { d, f };
  
  return lbi_syscall_6(a, b, c, n, e, x);
}

#define lb_syscall_5(n, a, b, c, d, e) lbi_syscall_5((a), (b), (c), (n), (e), (d))
#define lb_syscall_3(n, a, b, c)       lbi_syscall_3((a), (b), (c), (n))

#define lb_syscall_2(n, a, b)          lbi_syscall_2((a), (b), (n))
#define lb_syscall_1(n, a)             lbi_syscall_1((a), (n))
#define lb_syscall_0(n)                lbi_syscall_0((n))

#define lb_syscall_4(n, a, b, c, d) lb_syscall_5((n), (a), (b), (c), (d), (0))

#endif

#ifdef LB_ARCH_ARM_32

__asm__
(
  "lbi_syscall_6_asm:" LB_LF
  "push {r4,r5,r7}" LB_LF
  "ldr r4, [sp, #(3*4)]" LB_LF
  "ldr r5, [sp, #(4*4)]" LB_LF
  "ldr r7, [sp, #(5*4)]" LB_LF
  "swi #0" LB_LF
  "pop {r4,r5,r7}" LB_LF
  "mov pc, lr" LB_LF
  
  "lbi_syscall_5_asm:" LB_LF
  "push {r4,r7}" LB_LF
  "ldr r4, [sp, #(2*4)]" LB_LF
  "ldr r7, [sp, #(3*4)]" LB_LF
  "swi #0" LB_LF
  "pop {r4,r7}" LB_LF
  "mov pc, lr" LB_LF
  
  "lbi_syscall_4_asm:" LB_LF
  "push {r7}" LB_LF
  "ldr r7, [sp, #(1*4)]" LB_LF
  "swi #0" LB_LF
  "pop {r7}" LB_LF
  "mov pc, lr" LB_LF
  
  "lbi_syscall_3_asm:" LB_LF
  "push {r7}" LB_LF
  "mov r7, r3" LB_LF
  "swi #0" LB_LF
  "pop {r7}" LB_LF
  "mov pc, lr" LB_LF
  
  "lbi_syscall_2_asm:" LB_LF
  "push {r7}" LB_LF
  "mov r7, r2" LB_LF
  "swi #0" LB_LF
  "pop {r7}" LB_LF
  "mov pc, lr" LB_LF
  
  "lbi_syscall_1_asm:" LB_LF
  "push {r7}" LB_LF
  "mov r7, r1" LB_LF
  "swi #0" LB_LF
  "pop {r7}" LB_LF
  "mov pc, lr" LB_LF
  
  "lbi_syscall_0_asm:" LB_LF
  "push {r7}" LB_LF
  "mov r7, r0" LB_LF
  "swi #0" LB_LF
  "pop {r7}" LB_LF
  "mov pc, lr" LB_LF
);

extern intptr_t lbi_syscall_6(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e, uintptr_t f, uintptr_t n) __asm__("lbi_syscall_6_asm");
extern intptr_t lbi_syscall_5(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e, uintptr_t n)              __asm__("lbi_syscall_5_asm");
extern intptr_t lbi_syscall_4(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t n)                           __asm__("lbi_syscall_4_asm");
extern intptr_t lbi_syscall_3(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t n)                                        __asm__("lbi_syscall_3_asm");
extern intptr_t lbi_syscall_2(uintptr_t a, uintptr_t b, uintptr_t n)                                                     __asm__("lbi_syscall_2_asm");
extern intptr_t lbi_syscall_1(uintptr_t a, uintptr_t n)                                                                  __asm__("lbi_syscall_1_asm");
extern intptr_t lbi_syscall_0(uintptr_t n)                                                                               __asm__("lbi_syscall_0_asm");

#define lb_syscall_6(n, a, b, c, d, e, f) lbi_syscall_6((a), (b), (c), (d), (e), (f), (n))
#define lb_syscall_5(n, a, b, c, d, e)    lbi_syscall_5((a), (b), (c), (d), (e), (n))
#define lb_syscall_4(n, a, b, c, d)       lbi_syscall_4((a), (b), (c), (d), (n))
#define lb_syscall_3(n, a, b, c)          lbi_syscall_3((a), (b), (c), (n))
#define lb_syscall_2(n, a, b)             lbi_syscall_2((a), (b), (n))
#define lb_syscall_1(n, a)                lbi_syscall_1((a), (n))
#define lb_syscall_0(n)                   lbi_syscall_0((n))

#endif
