/*
  linuxtools
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

LB_MAIN_SPEC
{
#define MOREARGS ({                                                     \
      LB_ASSURE(argc > 0);                                              \
      argc;                                                             \
    })
  
#define CONSUME ({                                                      \
      MOREARGS;                                                         \
      argc--;                                                           \
      *(argv++);                                                        \
    })
  
  CONSUME;
  
  char const* cmd = CONSUME;
  
  /****/ if (lb_strcmp(cmd, "setuid")) {
    uintptr_t uid = lb_misc_narrow_64_ptr(lb_atou_64(CONSUME));
    intptr_t retv = lbt_setuid_bypass(uid);
    lb_print("susus", "linuxtools: setuid ", uid, " returned ", LB_UI(retv), "\n");
    MOREARGS;
    lbt_execve_bypass(argv[0], (argv + 1), envp);
    lbt_exit_group(1);
  } else if (lb_strcmp(cmd, "setgid")) {
    uintptr_t gid = lb_misc_narrow_64_ptr(lb_atou_64(CONSUME));
    intptr_t retv = lbt_setgid_bypass(gid);
    lb_print("susus", "linuxtools: setgid ", gid, " returned ", LB_UI(retv), "\n");
    MOREARGS;
    lbt_execve_bypass(argv[0], (argv + 1), envp);
    lbt_exit_group(1);
  } else {
    lb_print("s", "linuxtools: unknown command\n");
    lbt_exit_group(1);
  }
}
