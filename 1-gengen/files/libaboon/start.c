/*
  libaboon/start.c
  copyright (c) 2017 by andrei borac
*/

#ifdef LB_ARCH_X86_64

__asm__
(
  ".globl _start" LB_LF
  "_start:" LB_LF
  "mov %rsp, %rdi" LB_LF
  "callq lbi_start" LB_LF
  "lbi_start_return_loop:" LB_LF
  "jmp lbi_start_return_loop" LB_LF
);

#endif

#ifdef LB_ARCH_ARM_32

__asm__
(
  ".globl _start" LB_LF
  "_start:" LB_LF
  "mov r0, sp" LB_LF
  "bl lbi_start" LB_LF
  "libi_start_return_loop:" LB_LF
  "b libi_start_return_loop" LB_LF
);

#endif

#define LB_MAIN_SPEC                                                    \
  static void lb_main(uintptr_t argc LB_UNUSED, char const* const* argv LB_UNUSED, char const* const* envp LB_UNUSED)

LB_MAIN_SPEC;

void lbi_start(void*);

void lbi_start(void* rsp)
{
  lb_read_stack_pointer_check();
  
#if 0
  if (sizeof( int8_t)   != 1) LB_ILLEGAL;
  if (sizeof(uint8_t)   != 1) LB_ILLEGAL;
  if (sizeof( int16_t)  != 2) LB_ILLEGAL;
  if (sizeof(uint16_t)  != 2) LB_ILLEGAL;
  if (sizeof( int32_t)  != 4) LB_ILLEGAL;
  if (sizeof(uint32_t)  != 4) LB_ILLEGAL;
  if (sizeof( int64_t)  != 8) LB_ILLEGAL;
  if (sizeof(uint64_t)  != 8) LB_ILLEGAL;
#ifdef LB_ARCH_X86_64
  if (sizeof( intptr_t) != 8) LB_ILLEGAL;
  if (sizeof(uintptr_t) != 8) LB_ILLEGAL;
#endif
#ifdef LB_ARCH_ARM_32
  if (sizeof( intptr_t) != 4) LB_ILLEGAL;
  if (sizeof(uintptr_t) != 4) LB_ILLEGAL;
#endif
#endif
  
  if ((
       (sizeof( int8_t)   != 1) ||
       (sizeof(uint8_t)   != 1) ||
       (sizeof( int16_t)  != 2) ||
       (sizeof(uint16_t)  != 2) ||
       (sizeof( int32_t)  != 4) ||
       (sizeof(uint32_t)  != 4) ||
       (sizeof( int64_t)  != 8) ||
       (sizeof(uint64_t)  != 8) ||
#ifdef LB_ARCH_X86_64
       (sizeof( intptr_t) != 8) ||
       (sizeof(uintptr_t) != 8) ||
#endif
#ifdef LB_ARCH_ARM_32
       (sizeof( intptr_t) != 4) ||
       (sizeof(uintptr_t) != 4) ||
#endif
       false
       )) {
    LB_ILLEGAL;
  }
  
  uintptr_t* sp = ((uintptr_t*)(rsp));
  
  uintptr_t argc = *(sp++);
  char const* const* argv = ((char const *const *)(sp));
  sp += argc + 1;
  char const* const* envp = ((char const *const *)(sp));
  
  lb_main(argc, argv, envp);
  
  LB_ILLEGAL;
}
