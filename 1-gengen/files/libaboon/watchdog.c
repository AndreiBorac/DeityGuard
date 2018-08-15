/*
  libaboon/watchdog.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_watchdog_t)
{
  lb_alloc_t* ac;
  
  lb_thread_t* main;
  lb_thread_t* wdog;
  
  uintptr_t fd_timer;
  lbt_itimerspec_t itimerspec;
};

LB_SWITCH_PUSH_CLEANUP_VARIANT_1(_lb_watchdog_t, lb_watchdog_t*);
LB_SWITCH_CREATE_THREAD_VARIANT_1(_lb_watchdog_t, lb_watchdog_t*);

static void lbi_watchdog_cleanup(lb_thread_t* th, lb_watchdog_t* wd)
{
  LB_TR;
  lb_switch_destruct_thread(th, wd->wdog);
  LB_TR;
  lbt_close(wd->fd_timer);
  LB_TR;
  LB_ALLOC_FREE(wd, wd->ac);
  LB_TR;
}

static void lbi_watchdog_thread(lb_thread_t* th, lb_watchdog_t* wd)
{
  {
    uintptr_t const timer_event_size = 8;
    char buf[timer_event_size];
    lb_io_read_fully(th, wd->fd_timer, buf, timer_event_size);
  }
  LB_TR;
  lb_switch_destruct_thread(th, wd->main);
  LB_TR;
}

/*
  creates a watchdog that "irreversibly" watches the current
  thread. IMPORTANT: the watchdog is not armed here; rather, the first
  tickle arms the watchdog (and only if the interval has been set).
*/
static lb_watchdog_t* lb_watchdog_irreversible(lb_thread_t* th, lb_alloc_t* ac)
{
  LB_ALLOC_DECL(lb_watchdog_t, wd, ac);
  
  wd->ac = ac;
  wd->main = th;
  wd->fd_timer = LBT_OK(lbt_timerfd_create(lbt_CLOCK_MONOTONIC, lbt_TFD_NONBLOCK));
  LB_BZERO(wd->itimerspec);
  
  wd->wdog = lb_switch_create_thread__lb_watchdog_t(th->sw, lbi_watchdog_thread, wd);
  
  lb_switch_push_cleanup__lb_watchdog_t(th, lbi_watchdog_cleanup, wd);
  
  return wd;
}

/*
  runs proc with a watchdog. the watchdog is cleaned up after proc
  returns, and the return value from proc is passed
  through. IMPORTANT: the watchdog is not armed here; rather, the
  first tickle arms the watchdog (and only if the interval has been
  set).
*/
static void* lb_watchdog_passthrough(lb_thread_t* th, lb_alloc_t* ac, void* (*proc)(lb_thread_t*, lb_watchdog_t*, void*), void* parm)
{
  lb_watchdog_t* wd = lb_watchdog_irreversible(th, ac);
  
  void* retv = proc(th, wd, parm);
  
  lb_switch_pull_cleanup(th);
  
  lbi_watchdog_cleanup(th, wd);
  
  return retv;
}

/*
  tickle watchdog so that it does not trigger until the interval
  expires. if the interval has not been set yet, this has no effect;
  the watchdog timer remains unarmed.
*/
static void lb_watchdog_tickle(lb_watchdog_t* wd)
{
  LBT_OK(lbt_timerfd_settime(wd->fd_timer, 0, (&(wd->itimerspec)), NULL));
}

/*
  disables the watchdog until the next tickle/interval call. if set,
  the old interval is persisted to the next tickle.
*/
static void lb_watchdog_disable(lb_watchdog_t* wd)
{
  lbt_itimerspec_t itimerspec;
  
  LB_BZERO(itimerspec);
  
  LBT_OK(lbt_timerfd_settime(wd->fd_timer, 0, (&(itimerspec)), NULL));
}

/*
  set the watchdog interval to "ws" seconds and "ns" nanoseconds. "ns"
  must be under 1,000,000,000. this also arms the watchdog (except
  that setting a zero interval disables the watchdog).
*/
static void lb_watchdog_interval_hires(lb_watchdog_t* wd, uintptr_t ws, uintptr_t ns)
{
  wd->itimerspec.initial.sec  = ws;
  wd->itimerspec.initial.nsec = ns;
  
  lb_watchdog_tickle(wd);
}

/*
  set the watchdog interval to "ms" milliseconds (which can exceed
  1,000 if desired). this also arms the watchdog (except that setting
  a zero interval disables the watchdog).
*/
static void lb_watchdog_interval(lb_watchdog_t* wd, uintptr_t ms)
{
  lb_watchdog_interval_hires(wd, (ms / 1000), ((ms % 1000) * 1000000));
}
