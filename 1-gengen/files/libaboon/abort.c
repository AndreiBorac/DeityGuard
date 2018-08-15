/*
  libaboon/abort.c
  copyright (c) 2017 by andrei borac
*/

static void lbi_abort_second_chance(void)
{
  lb_breakpoint(0);
  
  lb_syscall_1(lbt_SYS_exit_group, lbt_EX_SOFTWARE);
  
  while (1);
}

static void lb_abort(void)
{
  lb_breakpoint(0);
  
  {
    uintptr_t v = (1 << (lbt_SIGABRT - 1));
    lb_syscall_4(lbt_SYS_rt_sigprocmask, lbt_SIG_UNBLOCK, LB_U(&v), 0, sizeof(v));
  }
  
  {
    intptr_t tid = lb_syscall_0(lbt_SYS_gettid);
    
    if (tid > 0) {
      lb_syscall_3(lbt_SYS_tgkill, LB_UI(tid), LB_UI(tid), lbt_SIGABRT);
    }
  }
  
  lbi_abort_second_chance();
  
  while (1);
}

#define LB_ABORT { lb_abort(); while (1); }

#define LBI_S__LINE__2(x) #x
#define LBI_S__LINE__1(x) LBI_S__LINE__2(x)
#define LBI_S__LINE__     LBI_S__LINE__1(__LINE__)

#if 0

/* the old way to implement assure */

#define LBI_ASSURE_FAILED_SPEC                                           \
  static void lbi_assure_failed(char const* file, char const* line, char const* expr)

LBI_ASSURE_FAILED_SPEC;

#define LB_ASSURE(expr) { if (!(expr)) { lbi_assure_failed(__FILE__, LBI_S__LINE__, #expr); }; };

#define LBI_ASSURE_COND(pref, expr, cond) ({ __typeof__(expr) LBI_ASSURE_COND__A; if (!(cond)) { lbi_assure_failed(__FILE__, LBI_S__LINE__, pref #expr); }; LBI_ASSURE_COND__A; })

#else

/*
  the new way - since it's a glob now, we don't actually need to defer
  the implementation until after printer.c
*/

#ifndef LB_STDIO_STDERR
#define LB_STDIO_STDERR 2
#endif

static void lbi_assure_write_string(char const* str)
{
  char const* end = str;
  
  while (*end) end++;

  while (str < end) {
    intptr_t amt = lb_syscall_3(lbt_SYS_write, LB_STDIO_STDERR, LB_U(str), LB_PTRDIF(end, str));
    if (amt <= 0) break;
    str += amt;
  }
}

static void lbi_assure_failed(char const* str)
{
  lbi_assure_write_string(str);
  
  LB_ABORT;
}

#ifndef LB_SPACE_OPTIMIZED
#define LBI_ASSURE_GLOB(pref, expr) pref ": (" __FILE__ ")[" LBI_S__LINE__ "]: (" expr ")\n"
#else
#define LBI_ASSURE_GLOB(pref, expr) "ERRUNK\n"
#endif

#define LB_ASSURE(expr) { if (!(expr)) { lbi_assure_failed(LBI_ASSURE_GLOB("assure", #expr)); } }

#define LBI_ASSURE_COND(pref, expr, cond) ({ __typeof__(expr) LBI_ASSURE_COND__A; if (!(cond)) { lbi_assure_failed(LBI_ASSURE_GLOB("assure: " pref, #expr)); }; LBI_ASSURE_COND__A; })

#endif

#define LB_ASSURE_EQZ(expr) LBI_ASSURE_COND( "EQZ" , expr , ((LBI_ASSURE_COND__A = (expr)) == 0))
#define LB_ASSURE_NEZ(expr) LBI_ASSURE_COND( "NEZ" , expr , ((LBI_ASSURE_COND__A = (expr)) != 0))
#define LB_ASSURE_LTZ(expr) LBI_ASSURE_COND( "LTZ" , expr , ((LBI_ASSURE_COND__A = (expr)) <  0))
#define LB_ASSURE_GTZ(expr) LBI_ASSURE_COND( "GTZ" , expr , ((LBI_ASSURE_COND__A = (expr)) >  0))
#define LB_ASSURE_LEZ(expr) LBI_ASSURE_COND( "LEZ" , expr , ((LBI_ASSURE_COND__A = (expr)) <= 0))
#define LB_ASSURE_GEZ(expr) LBI_ASSURE_COND( "GEZ" , expr , ((LBI_ASSURE_COND__A = (expr)) >= 0))

#define LB_ILLEGAL                                                      \
  {                                                                     \
    LB_ASSURE(false);                                                   \
    while (1);                                                          \
  }
