/*
  libaboon/heartbeat.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_heartbeat_t)
{
  uintptr_t fd_timer;
  
  uint64_t counter;
  
  lb_queue_t* qu;
  lb_work_queue_t* wq;
  
  void (*proc)(lb_thread_t*, uint64_t, void*);
  void*  user;
};

LB_SWITCH_CREATE_THREAD_VARIANT_1(_lbi_heartbeat_t, lb_heartbeat_t*);

static void lbi_heartbeat_thread(lb_thread_t* th, lb_heartbeat_t* hb)
{
  while (true) {
    uint64_t expirations;
    lb_io_read_fully(th, hb->fd_timer, (&(expirations)), sizeof(expirations));
    LB_ASSURE_GTZ(expirations);
    LB_PV(expirations);
    
    hb->counter += expirations;
    
    if (hb->qu) {
      lb_queue_push(hb->qu, (&(hb->counter)));
    }
    
    if (hb->wq) {
      lb_work_queue_submit(th, hb->wq, (&(hb->counter)));
    }
    
    if (hb->proc) {
      hb->proc(th, hb->counter, hb->user);
    }
  }
}

/*
  launches a heartbeat. either or both of proc and wq may be NULL or
  they may be both set. if they are both NULL, the heartbeat will
  still have the useful effect of waking the event loop every
  interval_ms, which will cause the improver to run. if they are both
  NULL and no improver was specified to the event loop either, then
  the heartbeat will still run but it will be completely useless.
  
  to the queue, the heartbeat pushes a pointer to the counter
  value. note that it's always the same pointer so it may appear to
  skip and repeat values if several heartbeats were queued up before
  being processed.
  
  values can even be skipped as seen by the proc if the heartbeat
  interval is so slow or the machine is so loaded that the heartbeat
  thread can't keep up with processing each timer event.
  
  the counter *is* guaranteed to always increase, however, and this is
  perhaps the only property that applications should rely on.
  
  the first counter value is always 1 (not zero!).
  
  nothing is returned by this function because it is not supported to
  stop or otherwise control the heartbeat once it is launched.
*/
static void lb_heartbeat_launch(lb_switch_t* sw, lb_alloc_t* ac, uintptr_t interval_ms, lb_queue_t* qu, lb_work_queue_t* wq, void (*proc)(lb_thread_t*, uint64_t, void*), void* user)
{
  LB_ALLOC_DECL(lb_heartbeat_t, hb, ac);
  
  hb->fd_timer = LBT_OK(lbt_timerfd_create(lbt_CLOCK_MONOTONIC, lbt_TFD_NONBLOCK));
  
  hb->counter = 0;
  
  hb->qu = qu;
  hb->wq = wq;
  
  hb->proc = proc;
  hb->user = user;
  
  lbt_itimerspec_t itimerspec;
  LB_BZERO(itimerspec);
  itimerspec.interval.sec  = ((interval_ms / 1000)          );
  itimerspec.interval.nsec = ((interval_ms % 1000) * 1000000);
  itimerspec.initial = itimerspec.interval;
  
  LBT_OK(lbt_timerfd_settime(hb->fd_timer, 0, (&(itimerspec)), NULL));
  
  lb_switch_create_thread__lbi_heartbeat_t(sw, lbi_heartbeat_thread, hb);
}

#define LB_HEARTBEAT_LAUNCH_VARIANT_1(s, a)                             \
  static void lb_heartbeat_launch_##s(lb_thread_t* th, lb_alloc_t* ac, uintptr_t interval_ms, lb_work_queue_t* wq, void (*proc)(lb_thread_t*, uint64_t, a), a user_a) \
  {                                                                     \
    LB_ASSURE((sizeof(a) == sizeof(uintptr_t)));                        \
    lb_heartbeat_launch(th, ac, interval_ms, wq, ((void (*)(lb_thread_t*, uint64_t, void*))(proc)), ((void*)(user_a)), NULL, NULL); \
  }
