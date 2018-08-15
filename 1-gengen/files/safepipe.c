/*
  safepipe - a pipeline safeifier
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

#define TR LB_TR
#define PV LB_PV
#define AV LB_AV
#define DG LB_DG

static void write_fully_fd(uintptr_t fd, uint8_t const* buf, uintptr_t len)
{
  uint8_t const* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_write(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}

LB_MAIN_SPEC
{
  bool allow[256];
  
  LB_BZERO(allow);
  
  LB_ASSURE((argc == 3));
  
  {
    char const* spec = argv[1];
    
    while (*spec) {
      char char_lo = (*(spec++));
      char char_hi = (*(spec++));
      
      LB_ASSURE(char_hi);
      
      uintptr_t lo = (LB_U(char_lo) & 0xFF);
      uintptr_t hi = (LB_U(char_hi) & 0xFF);
      
      while (lo <= hi) {
        allow[lo] = true;
        lo++;
      }
    }
  }
  
  char const* repl = argv[2];
  
  LB_ASSURE(lb_strlen(repl) == 1);
  
  {
    uint8_t buf[512];
    
    {
      intptr_t retv;
      
      while ((retv = lbt_read(0, buf, sizeof(buf))) > 0) {
        uintptr_t len = LB_UI(retv);
        
        for (uintptr_t i = 0; i < len; i++) {
          if (!(allow[buf[i]])) {
            buf[i] = (LB_U(repl[0]) & 0xFF);
          }
        }
        
        write_fully_fd(1, buf, len);
      }
    }
  }
  
  lbt_exit_simple(0);
  
  LB_ABORT;
}
