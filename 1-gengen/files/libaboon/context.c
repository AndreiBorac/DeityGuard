/*
  libaboon/context.c
  copyright (c) 2017 by andrei borac
*/

#ifdef LB_ARCH_X86_64

__asm__
(
  // rdi = &rsp_old
  // rsi =  rsp_new
  // rdx =  rax
  "lbi_context_switch_asm:" LB_LF
  /**/
  "pushq %rbp" LB_LF
  "pushq %rbx" LB_LF
  "pushq %r12" LB_LF
  "pushq %r13" LB_LF
  "pushq %r14" LB_LF
  "pushq %r15" LB_LF
  /**/
  "movq %rsp, (%rdi)" LB_LF
  "movq %rsi,  %rsp " LB_LF
  /**/
  "popq %r15" LB_LF
  "popq %r14" LB_LF
  "popq %r13" LB_LF
  "popq %r12" LB_LF
  "popq %rbx" LB_LF
  "popq %rbp" LB_LF
  /**/
  "movq %rdx,  %rax " LB_LF
  /**/
  "retq" LB_LF
);

#endif

#ifdef LB_ARCH_ARM_32

__asm__
(
  // r0 - &rsp_old
  // r1 -  rsp_new
  // r2 -       r0
  "lbi_context_switch_asm:" LB_LF
  /**/
  "push {r4-r11,r14}" LB_LF
  /**/
  "str sp, [r0]" LB_LF
  "mov sp, r1" LB_LF
  /**/
  "pop {r4-r11,r14}" LB_LF
  "mov r0, r2" LB_LF
  /**/
  "mov pc, lr" LB_LF
);

#endif

extern void* lbi_context_switch(uintptr_t* rsp_old, uintptr_t rsp, uintptr_t rax) __asm__("lbi_context_switch_asm");

typedef struct
{
  uintptr_t rsp;
}
lb_context_t;

typedef struct
{
  uintptr_t rsp_peer;
  uintptr_t rax;
}
lb_context_state_t;

typedef struct
{
  uintptr_t addr;
}
lb_context_proc_t;

#define LB_CONTEXT_PROC(name)                                           \
  static void name##_proc_proc(lb_context_state_t* lb)                  \
  {                                                                     \
    lb_context_state_t cs = *lb;                                        \
    name(&cs, ((void*)(cs.rax)));                                       \
    LB_ILLEGAL;                                                         \
  }                                                                     \
                                                                        \
  lb_context_proc_t const name##_proc = { .addr = LB_U(name##_proc_proc) };

/*
  initializes the given context to run the given proc. the proc should
  not return. this mutates the stack contents, so it should -not- be
  called from a context running on the same stack.
  
  stacks are in general not position independent because they can
  contain addresses; -however-, the stack configuration output here is
  guaranteed to be position-independent.
*/
static void lb_context_initialize(lb_context_t* cx, void* stack_base, uintptr_t stack_size, lb_context_proc_t proc)
{
  uintptr_t stack_endp = ((uintptr_t)(stack_base + stack_size));
  
  stack_endp &= (~(16UL - 1));           // align
  stack_endp -= (4 * sizeof(uintptr_t)); // safety margin
  
#ifdef LB_ARCH_X86_64
  
  // we need do nothing to account for the "red zone" because it is on the other side of the stack
  
  struct {
    uint64_t  r15;
    uint64_t  r14;
    uint64_t  r13;
    uint64_t  r12;
    uint64_t  rbx;
    uint64_t  rbp;
    uintptr_t ret;
  } *s;
  
  // the extra subtract is for stack alignment
  s = ((__typeof__(s))(stack_endp - sizeof(*s) - sizeof(uintptr_t)));
  
  s->r15 = 15;
  s->r14 = 14;
  s->r13 = 13;
  s->r12 = 12;
  s->rbx = 11;
  s->rbp = 0;
  s->ret = proc.addr;
  
#endif
  
#ifdef LB_ARCH_ARM_32
  
  struct {
    uintptr_t r4;
    uintptr_t r5;
    uintptr_t r6;
    uintptr_t r7;
    uintptr_t r8;
    uintptr_t r9;
    uintptr_t r10;
    uintptr_t r11;
    uintptr_t lr;
  } *s;
  
  s = ((__typeof__(s))(stack_endp - sizeof(*s)));
  
  s->r4 = 4;
  s->r5 = 5;
  s->r6 = 6;
  s->r7 = 7;
  s->r8 = 8;
  s->r9 = 9;
  s->r10 = 10;
  s->r11 = 11;
  s->lr = proc.addr;
  
#endif
  
  cx->rsp = LB_U(s);
}

/*
  returns rax to the caller of lb_context_enter.
*/
static void* lb_context_yield(lb_context_state_t* cs, void* rax)
{
  cs->rax = LB_U(rax);
  LB_DG("sus", "lb_context_yield: going to ", cs->rsp_peer, "\n");
  lb_context_state_t* from = ((lb_context_state_t*)(lbi_context_switch((&(cs->rsp_peer)), (cs->rsp_peer), LB_U(cs))));
  cs->rsp_peer = from->rsp_peer;
  return ((void*)(from->rax));
}

/*
  executes the given context. rax is returned to that context from
  yield (or, for the first invocation, passed as the user
  data). returns the argument to yield.
*/
static void* lb_context_enter(lb_context_t* cx, void* rax)
{
  lb_context_state_t  from = { .rax = LB_U(rax) };
  LB_DG("sus", "lb_context_enter: going to ", cx->rsp, "\n");
  lb_context_state_t* retv = ((lb_context_state_t*)(lbi_context_switch((&(from.rsp_peer)), (cx->rsp), LB_U(&(from)))));
  cx->rsp = retv->rsp_peer;
  return ((void*)(retv->rax));
}
