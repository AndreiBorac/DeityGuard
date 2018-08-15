/*
  fanman
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

#define TR LB_TR

static uintptr_t z_read_atou(uintptr_t fd)
{
  uintptr_t retv = 0;
  
  {
    unsigned char buf;
    
    while (lbt_read(fd, (&buf), sizeof(buf)) == 1) {
      if ((buf == ' ') || (buf == '\n')) return retv;
      LB_ASSURE((('0' <= buf) && (buf <= '9')));
      retv = ((retv << 3) + (retv << 1) + LB_U(buf - '0'));
    }
  }
  
  return retv;
}

static void z_write_fully(uintptr_t fd, unsigned char const* buf, uintptr_t len)
{
  while (len > 0) {
    intptr_t amt = lbt_write(fd, buf, len);
    LB_ASSURE_GTZ(amt);
    uintptr_t amt_u = LB_UI(amt);
    buf += amt_u;
    len -= amt_u;
  }
}

static void z_write_fully_string(uintptr_t fd, char const* str)
{
  z_write_fully(fd, ((unsigned char const*)(str)), lb_strlen(str));
}

LB_MAIN_SPEC
{
  char const* consumed;
  
#define CONSUME_ARG                                                     \
    {                                                                   \
      LB_ASSURE(argc > 0);                                              \
      consumed = argv[0];                                               \
      argv++;                                                           \
      argc--;                                                           \
    }
  
#define CONSUME_ARG_STRING(what_var)                                    \
  CONSUME_ARG;                                                          \
  char const* what_var = consumed;
  
#define CONSUME_ARG_ATOU(what_var)                                      \
  CONSUME_ARG;                                                          \
  uintptr_t what_var = lb_misc_narrow_64_ptr(lb_atou_64(consumed));
  
  CONSUME_ARG; // program name
  
  CONSUME_ARG_ATOU(celsius_fdn); // number of temperature input files
  uintptr_t celsius_fds[celsius_fdn];
  
  for (uintptr_t i = 0; i < celsius_fdn; i++) {
    CONSUME_ARG; // next temperature input file
    celsius_fds[i] = LB_U(LB_ASSURE_GEZ(lbt_open(consumed, lbt_O_RDONLY, 0)));
  }
  
  CONSUME_ARG_ATOU(fanctrl_fdn); // number of pwm files
  uintptr_t fanctrl_fds[fanctrl_fdn];
  
  for (uintptr_t i = 0; i < fanctrl_fdn; i++) {
    CONSUME_ARG; // next temperature input file
    fanctrl_fds[i] = LB_U(LB_ASSURE_GEZ(lbt_open(consumed, lbt_O_WRONLY, 0)));
  }
  
  CONSUME_ARG_ATOU(param_celsius_lo);
  CONSUME_ARG_ATOU(param_celsius_hi);
  CONSUME_ARG_STRING(param_pwm_idle);
  CONSUME_ARG_STRING(param_pwm_full);
  
  char const* pwm_last = param_pwm_full;
  
  LB_ASSURE_EQZ(lbt_mlockall_bypass((lbt_MCL_CURRENT | lbt_MCL_FUTURE)));
  
  while (1) {
    uintptr_t celsius_max = 0;
    
    for (uintptr_t i = 0; i < celsius_fdn; i++) {
      lbt_lseek_bypass(celsius_fds[i], 0, lbt_SEEK_SET);
      uintptr_t celsius_cur = z_read_atou(celsius_fds[i]);
      if (celsius_cur > celsius_max) celsius_max = celsius_cur;
    }
    
    lb_print("us", celsius_max, "\n");
    
    if (celsius_max <  param_celsius_lo) {
      pwm_last = param_pwm_idle;
    }
    
    if (celsius_max >= param_celsius_hi) {
      pwm_last = param_pwm_full;
    }
    
    for (uintptr_t i = 0; i < fanctrl_fdn; i++) {
      z_write_fully_string(fanctrl_fds[i], pwm_last);
    }
    
    lbt_nanosleep_bypass(1, 0);
  }
}
