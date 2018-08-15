/*
  libaboon/everything.c
  copyright (c) 2017 by andrei borac
*/

#define LB_CURRENT_FILE 101
#include "./definitions.c"
#include "./syscall.c"
#include "./abort.c"
#include "./sysdeps.c"
#include "./divide.c"
#include "./string.c"
#include "./printer.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 102
#include "./start.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 103
#include "./context.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 104
#include "./linux.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 105
#include "./alloc.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 106
#include "./stack.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 107
#include "./queue.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 108
#include "./switch.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 109
#include "./token_bucket.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 110
#include "./work_queue.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 111
#include "./io.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 112
#include "./aio.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 113
#include "./bufio.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 114
#include "./heartbeat.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 115
#include "./watchdog.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 116
#include "./misc.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 117
#include "./sha256.c"
#undef  LB_CURRENT_FILE

#define LB_CURRENT_FILE 118
#include "./type_magic.c"
#undef  LB_CURRENT_FILE

#ifndef LB_EVERYTHING_NO_BIGNUM
#ifdef LB_ARCH_ANY_64
#define LB_CURRENT_FILE 119
#include "./bignum.c"
#undef  LB_CURRENT_FILE
#endif
#endif

#define LB_CURRENT_FILE 0
