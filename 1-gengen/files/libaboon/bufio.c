/*
  libaboon/bufio.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_bufio_t)
{
  uint8_t* bas;
  uint8_t* lim;
  uint8_t* cur;
  uint8_t* end;
  bool     eof;
};

static lb_bufio_t* lb_bufio_create(lb_alloc_t* ac, uintptr_t bufsiz)
{
  LB_ALLOC_DECL(lb_bufio_t, bu, ac);
  
  bu->bas = ((uint8_t*)(lb_alloc(ac, bufsiz)));
  bu->lim = (bu->bas + bufsiz);
  bu->cur = bu->lim;
  bu->end = bu->lim;
  bu->eof = false;
  
  return bu;
}

static void lb_bufio_delete(lb_bufio_t* bu, lb_alloc_t* ac)
{
  lb_alloc_free(ac, bu->bas, LB_PTRDIF(bu->lim, bu->bas));
  
  LB_ALLOC_FREE(bu, ac);
}

static uintptr_t lb_bufio_read(lb_bufio_t* bu, uintptr_t fd, void* buf_par, uintptr_t len_par)
{
  uint8_t* buf = (((uint8_t*)(buf_par)));
  uint8_t* lim = (buf + len_par);
  
  while (true) {
    /* give from what we have */
    {
      uintptr_t amt = LB_U(LB_MIN((bu->end - bu->cur), (lim - buf)));
      lb_memcpy(buf, bu->cur, amt);
      buf += amt;
      bu->cur += amt;
    }
    
    /*
      if that was enough, get gone! also get gone if we are at EOF
    */
    {
      if ((bu->eof) || (!(buf < lim))) {
        return LB_PTRDIF(buf, buf_par);
      }
    }
    
    /* try to refill the buffer */
    {
      intptr_t amt = lbt_read(fd, bu->bas, LB_PTRDIF(bu->lim, bu->bas));
      
      LB_ASSURE(amt >= 0);
      
      bu->cur = bu->bas;
      bu->end = (bu->bas + amt);
      bu->eof = (amt == 0);
    }
  }
}
