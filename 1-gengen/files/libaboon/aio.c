/*
  libaboon/aio.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_aio_hub_t)
{
  lb_alloc_t* ac;
  
  uintptr_t fd_event;
  
  uintptr_t ctx;
  
  uintptr_t nfl; /* numver of requests in-flight */
  uintptr_t max;
  
  lb_queue_t* qu_wtg; /* waiting */
  lb_queue_t* qu_out; /* ready */
};

LB_TYPEBOTH(lbi_aio_req_t)
{
  uintptr_t fdi;
  uintptr_t buf;
  uintptr_t len;
  uint64_t  off;
  void*     usr;
  uintptr_t opc;
};

static void lbi_aio_hub_submit_helper(lb_aio_hub_t* ah, uintptr_t fd, uintptr_t buf, uintptr_t len, uint64_t off, void* user, uintptr_t opcode)
{
  lbt_iocb_t   iocb;
  lbt_iocb_t*  iocbp  = (&(iocb));
  lbt_iocb_t** iocbpp = (&(iocbp));
  
  LB_BZERO(iocb);
  
  iocb.aio_data = ((uint64_t)((uintptr_t)(user)));
  iocb.aio_fildes = ((uint32_t)(fd));
  iocb.aio_lio_opcode = ((uint16_t)(opcode));
  iocb.aio_buf = buf;
  iocb.aio_nbytes = len;
  iocb.aio_offset = off;
  iocb.aio_flags = lbt_IOCB_FLAG_RESFD;
  iocb.aio_eventfd = ((uint32_t)(ah->fd_event));
  
  LB_AV(user, "submit");
  LB_ASSURE(lbt_io_submit(ah->ctx, 1, iocbpp) == 1);
  
  ah->nfl++;
}

static LB_NO_INLINE void lbi_aio_hub_thread_helper(lb_aio_hub_t* ah, uintptr_t num)
{
  while (num > 0) {
    /* pull events */
    {
      lbt_io_event_t evt[num];
      
      LB_AV(num, "entering getevents");
      intptr_t amt_signed = lbt_io_getevents(ah->ctx, num, num, evt, NULL);
      LB_AV(amt_signed, "left getevents");
      LB_ASSURE_GTZ(amt_signed);
      uintptr_t amt = LB_UI(amt_signed);
      num -= amt;
      
      ah->nfl -= amt;
      
      for (uintptr_t i = 0; i < amt; i++) {
        /*
          check that the I/O succeeded. we don't support failure yet.
        */
        LB_PV(evt[i].res);
        LB_ASSURE((evt[i].res >= 0));
        
        lb_queue_push(ah->qu_out, ((void*)((uintptr_t)(evt[i].data))));
      }
    }
    
    /* resubmit queued */
    {
      uintptr_t amt = LB_MIN(lb_queue_size(ah->qu_wtg), (ah->max - ah->nfl));
      
      while ((amt--) > 0) {
        lbi_aio_req_t* req = ((lbi_aio_req_t*)(lb_queue_pull(ah->qu_wtg)));
        
        lbi_aio_hub_submit_helper(ah, req->fdi, req->buf, req->len, req->off, req->usr, req->opc);
        
        LB_ALLOC_FREE(req, ah->ac);
      }
    }
  }
}

static void lbi_aio_hub_thread(lb_thread_t* th, lb_aio_hub_t* ah)
{
  while (true) {
    uint64_t num;
    
    LB_AV(ah, "enter read block");
    lb_io_read_fully(th, ah->fd_event, (&(num)), sizeof(num));
    LB_AV(ah, "leave read block");
    
    uintptr_t num2 = ((uintptr_t)(num));
    
#ifdef LB_ARCH_ARM_32
    LB_ASSURE(num2 == num);
#endif
    
    lbi_aio_hub_thread_helper(ah, num2);
  }
}

LB_SWITCH_CREATE_THREAD_VARIANT_1(_lbi_aio, lb_aio_hub_t*);

static lb_aio_hub_t* lb_aio_hub_create(lb_switch_t* sw, lb_alloc_t* ac, uintptr_t max, lb_queue_t* qu_out)
{
  LB_ASSURE((max > 0));
  
  LB_ALLOC_DECL(lb_aio_hub_t, ah, ac);
  
  ah->ac = ac;
  
  ah->fd_event = LBT_OK(lbt_eventfd2(0, lbt_EFD_NONBLOCK));
  
  LBT_OK(lbt_io_setup(max, (&(ah->ctx))));
  
  ah->nfl = 0;
  ah->max = max;
  
  ah->qu_wtg = lb_queue_create(ac);
  ah->qu_out = qu_out;
  
  lb_switch_create_thread__lbi_aio(sw, lbi_aio_hub_thread, ah);
  
  return ah;
}

static void lbi_aio_hub_submit(lb_aio_hub_t* ah, uintptr_t fd, uintptr_t buf, uintptr_t len, uint64_t off, void* user, uintptr_t opcode)
{
  if (ah->nfl < ah->max) {
    lbi_aio_hub_submit_helper(ah, fd, buf, len, off, user, opcode);
  } else {
    LB_ALLOC_DECL(lbi_aio_req_t, req, ah->ac);
    
    req->fdi = fd;
    req->buf = buf;
    req->len = len;
    req->off = off;
    req->usr = user;
    req->opc = opcode;
    
    lb_queue_push(ah->qu_wtg, req);
  }
}

static LB_INLINE void lb_aio_hub_submit_read(lb_aio_hub_t* ah, uintptr_t fd, void* buf, uintptr_t len, uint64_t off, void* user)
{
  lbi_aio_hub_submit(ah, fd, LB_U(buf), len, off, user, lbt_IOCB_CMD_PREAD);
}

static LB_INLINE void lb_aio_hub_submit_write(lb_aio_hub_t* ah, uintptr_t fd, void const* buf, uintptr_t len, uint64_t off, void* user)
{
  lbi_aio_hub_submit(ah, fd, LB_U(buf), len, off, user, lbt_IOCB_CMD_PWRITE);
}

static LB_INLINE void lb_aio_hub_submit_fsync(lb_aio_hub_t* ah, uintptr_t fd, void* user)
{
  lbi_aio_hub_submit(ah, fd, LB_U(NULL), 0, 0, user, lbt_IOCB_CMD_FSYNC);
}

static LB_INLINE void lb_aio_hub_submit_fdsync(lb_aio_hub_t* ah, uintptr_t fd, void* user)
{
  lbi_aio_hub_submit(ah, fd, LB_U(NULL), 0, 0, user, lbt_IOCB_CMD_FDSYNC);
}
