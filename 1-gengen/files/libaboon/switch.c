/*
  libaboon/switch.c
  copyright (c) 2017 by andrei borac
*/

#ifndef LB_THREAD_PAGE_SIZE
#define LB_THREAD_PAGE_SIZE 4096
#endif

#ifndef LB_SWITCH_SIMULTANEOUS_EVENTS
#define LB_SWITCH_SIMULTANEOUS_EVENTS 16
#endif

#ifndef LB_SWITCH_CLEANUP_LIMIT
#define LB_SWITCH_CLEANUP_LIMIT 8
#endif

struct struct_lbi_thread_page_t;
typedef struct struct_lbi_thread_page_t lbi_thread_page_t;

struct struct_lb_thread_t;
struct struct_lb_switch_t;

typedef struct struct_lb_thread_t lb_thread_t;
typedef struct struct_lb_switch_t lb_switch_t;

typedef void (*lb_switch_cleanup_proc_t)(lb_thread_t*, void*, void*, void*);

struct struct_lbi_thread_page_t
{
  lbi_thread_page_t* next;
  uint8_t data[0];
};

struct struct_lb_thread_t
{
  lb_switch_t* sw;
  
  bool         runnable;
  void*        runnable_retv;
  lb_thread_t* runnable_next;
  
  bool slumber_enabled;
  
  bool      epoll_enabled;
  uintptr_t epoll_fd;
  
  bool destruct_enabled;
  
  /*
    cleanup data.
  */
  uintptr_t    cleanup_stack_len;
  struct {
    lb_switch_cleanup_proc_t proc;
    void*                    user_a;
    void*                    user_b;
    void*                    user_c;
  }            cleanup_stack_arr[LB_SWITCH_CLEANUP_LIMIT];
  
  /*
    hibernation data. the hiber_page_list can be NULL to indicate a
    zombie to be cleaned up.
  */
  lb_context_t       hiber_thread_cx;
  uintptr_t          hiber_stack_len;
  lbi_thread_page_t* hiber_page_list;
  
  /*
    context-interactive state data.
  */
  union {
    struct {
      void (*proc)(lb_thread_t* th, void*);
      void* user;
    } i;
    
    struct {
      lb_context_state_t cs;
    } x;
  } u;
};

struct struct_lb_switch_t
{
  lb_alloc_t* ac;
  
  /*
    list of free pages not assigned to any thread.
  */
  lbi_thread_page_t* page_list;
  
  /*
    the currently running thread. NULL before the first invocation of
    event_loop, and when running code in the event_loop.
  */
  lb_thread_t* current;
  
  /*
    indicates to the switch that the current thread to is to be
    destructed. only the current thread uses this mechanism to
    destruct; desctruction of other threads is immediate.
  */
  bool destruct_me;
  
  /*
    "runnable" threads are those waiting to run that are not blocked
    in epoll. the current thread is never in this list. the switch
    does not ever enter epoll unless there are no runnable
    threads. also, the threads are not run in round robin order but
    rather in stack order. so "yield" cannot be implemented.
  */
  lb_thread_t* runnable_list;
  
  /*
    epoll_fd - file descriptor of the epoll instance.
    
    epoll_nr - number of threads with a registered file descriptor in
    epoll.
  */
  uintptr_t epoll_fd;
  uintptr_t epoll_nr;
  
  uintptr_t stack_base;
  
  uintptr_t destruct_nesting;
};

static void lb_switch_initialize(lb_switch_t* sw, lb_alloc_t* ac)
{
  sw->ac = ac;
  
  sw->page_list = NULL;
  
  sw->current = NULL;
  
  sw->destruct_me = false;
  
  sw->runnable_list = NULL;
  
  sw->epoll_fd = LBT_OK(lbt_epoll_create1(0));
  sw->epoll_nr = 0;
  
  sw->stack_base = 0;
  
  sw->destruct_nesting = 0;
}

static void lbi_switch_add_runnable(lb_switch_t* sw, lb_thread_t* th, void* retv)
{
  LB_ASSURE(!(th->runnable));
  th->runnable = true;
  th->runnable_retv = retv;
  th->runnable_next = th->sw->runnable_list;
  sw->runnable_list = th;
}

static lbi_thread_page_t* lbi_switch_page_obtain(lb_switch_t* sw)
{
  if (sw->page_list) {
    lbi_thread_page_t* retv = sw->page_list;
    sw->page_list = sw->page_list->next;
    return retv;
  } else {
    return ((lbi_thread_page_t*)(lb_alloc(sw->ac, LB_THREAD_PAGE_SIZE)));
  }
}

static void lbi_switch_page_return(lb_switch_t* sw, lbi_thread_page_t* tp)
{
  tp->next = sw->page_list;
  sw->page_list = tp;
}

static void lbi_switch_entrypoint_proc(lb_context_state_t* vl)
{
  lb_thread_t* th;
  LB_CAST_ASGN(th, vl->rax);
  
  __typeof__(th->u.i) th_u_i = th->u.i;
  
  th->u.x.cs = *vl;
  
  th_u_i.proc(th, th_u_i.user);
  
  LB_ILLEGAL;
}

static lb_thread_t* lb_switch_create_thread(lb_switch_t* sw, void (*proc)(lb_thread_t*, void*), void* user)
{
  LB_ALLOC_DECL(lb_thread_t, th, sw->ac);
  
  LB_AV(th, "thread.valid=true");
  
  th->sw = sw;
  th->runnable = false;
  th->slumber_enabled = false;
  th->epoll_enabled = false;
  th->destruct_enabled = false;
  th->cleanup_stack_len = 0;
  th->u.i.proc = proc;
  th->u.i.user = user;
  
  lbi_thread_page_t* tp = lbi_switch_page_obtain(sw);
  tp->next = NULL;
  
  uintptr_t stack_base = LB_U(tp);
  uintptr_t stack_endp = (stack_base + LB_THREAD_PAGE_SIZE);
  
  lb_context_initialize((&(th->hiber_thread_cx)), tp, LB_THREAD_PAGE_SIZE, ((lb_context_proc_t){ .addr = LB_U(lbi_switch_entrypoint_proc) }));
  
  LB_PV(th->hiber_thread_cx.rsp);
  LB_PV(stack_endp);
  th->hiber_thread_cx.rsp -= stack_endp;
  
  th->hiber_stack_len = (-(th->hiber_thread_cx.rsp));
  LB_PV(th->hiber_stack_len);
  th->hiber_page_list = tp;
  
  lbi_switch_add_runnable(sw, th, th);
  
  return th;
}

#define LB_SWITCH_CREATE_THREAD_VARIANT_0(s)                            \
  static lb_thread_t* lb_switch_create_thread_##s(lb_switch_t* sw, void (*proc)(lb_thread_t*)) \
  {                                                                     \
    return lb_switch_create_thread(sw, ((void (*)(lb_thread_t*, void*))(proc)), NULL); \
  }

#define LB_SWITCH_CREATE_THREAD_VARIANT_1(s, a)                         \
  static lb_thread_t* lb_switch_create_thread_##s(lb_switch_t* sw, void (*proc)(lb_thread_t*, a), a user) \
  {                                                                     \
    LB_ASSURE((sizeof(a) == sizeof(uintptr_t)));                        \
    return lb_switch_create_thread(sw, ((void (*)(lb_thread_t*, void*))(proc)), ((void*)(user))); \
  }

#define LBI_SWITCH_PAGE_CONSUME                                         \
  lbi_thread_page_t* tp_next = tp->next;                                \
  lbi_switch_page_return(sw, tp);                                       \
  tp = tp_next;                                                         \

static void lbi_switch_destruct_thread(lb_switch_t* sw, lb_thread_t* th)
{
  /*
    logic bug if the thread has epoll enabled at this point.
  */
  LB_ASSURE((!(th->epoll_enabled)));
  
  LB_AV(th, "thread.valid=false");
  
  /*
    consume the thread's hibernation pages.
  */
  {
    lbi_thread_page_t* tp = th->hiber_page_list;
    
    while ((tp != NULL)) {
      LBI_SWITCH_PAGE_CONSUME;
    }
  }
  
#if 0
  /*
    take the thread out of runnable if it's there.
  */
  {
    lb_thread_t** runnable_walk = (&(sw->runnable_list));
    
    while ((*(runnable_walk)) != NULL) {
      if ((*(runnable_walk)) == th) {
        (*(runnable_walk)) = th->runnable_next;
        break;
      }
      
      runnable_walk = (&((*(runnable_walk))->runnable_next));
    }
  }
#else
  /*
    if the thread is in runnable, we can't axe it right away but must
    wait for the event loop to dequeue it and take care of it.
  */
  {
    if (th->runnable) {
      th->hiber_page_list = NULL;
    } else {
      LB_ALLOC_FREE(th, sw->ac);
    }
  }
#endif
}

#define LBI_SWITCH_CURRENT_THREAD_ONLY { LB_ASSURE((th == th->sw->current)); }
#define LBI_SWITCH_SAME_SWITCH_ONLY    { LB_ASSURE((th->sw == th_target->sw)); }

static void lbi_switch_epoll_disable(lb_thread_t* th)
{
  LB_ASSURE(th->epoll_enabled);
  th->epoll_enabled = false;
  
  LB_DG("susus", "epoll_ctl DEL th ", LB_U(th), " fd ", th->epoll_fd, "\n");
  LB_ASSURE_EQZ(lbt_epoll_ctl(th->sw->epoll_fd, lbt_EPOLL_CTL_DEL, th->epoll_fd, NULL));
  th->sw->epoll_nr--;
}

#define LBI_SWITCH_SAFETY_ZONE (8*1024)
#define LBI_SWITCH_TRAIN_SKIP 512

static void lbi_print_stack(char const* inf, lb_thread_t* th, uintptr_t rsp, uintptr_t bas)
{
  LB_DG("susss", "lbi_print_stack for ", LB_U(th), " on ", inf, "\n");
  
  while (rsp < bas) {
    LB_DG("susus", "stack[rsp=", rsp, "]=", (*((uintptr_t*)(rsp))), "\n");
    rsp += 8;
  }
  
  LB_DG("s", "done\n");
}

static void lbi_switch_prepare_stack(uintptr_t stack_base)
{
  for (uintptr_t i = 0 ; i < (LBI_SWITCH_SAFETY_ZONE) ; i += LBI_SWITCH_TRAIN_SKIP) {
    (*((uintptr_t volatile*)(stack_base - i)));
  }
}

static void* lbi_switch_load_exec_save(lb_switch_t* sw, lb_thread_t* th, void* retv)
{
  uintptr_t stack_base = lb_read_stack_pointer();
  
  if (sw->stack_base == 0) {
    sw->stack_base = stack_base;
    lbi_switch_prepare_stack(stack_base);
  }
  
  LB_ASSURE((stack_base == sw->stack_base));
  
  stack_base -= LBI_SWITCH_SAFETY_ZONE;
  
  uintptr_t const page_capacity = (LB_THREAD_PAGE_SIZE - __builtin_offsetof(lbi_thread_page_t, data));
  
  // copy in
  {
    LB_DG("sus", "switch-copy-in: ", LB_U(th), "\n");
    
    uintptr_t rsp = stack_base;
    LB_AV(rsp, "= stack_base");
    
    uintptr_t rem = th->hiber_stack_len;
    LB_PV(rem);
    
    lbi_thread_page_t* tp = th->hiber_page_list;
    
    void do_amt(uintptr_t amt) {
      rsp -= amt;
      
      LB_PV(tp);
      LB_PV((tp->data + (page_capacity - amt)));
      LB_PV(rsp);
      LB_PV(amt);
      lb_memcpy(((void*)(rsp)), (tp->data + (page_capacity - amt)), amt);
      LBI_SWITCH_PAGE_CONSUME;
      
      rem -= amt;
    }
    
    while (rem >= page_capacity) {
      do_amt(page_capacity);
    }
    
    if (rem > 0) {
      do_amt(rem);
    }
    
    LB_PV(rsp);
    
    LB_ASSURE((tp == NULL));
  }
  
  // exec
  th->hiber_thread_cx.rsp += stack_base;
  //lbi_print_stack("enter", th, th->hiber_thread_cx.rsp, stack_base);
  retv = lb_context_enter((&(th->hiber_thread_cx)), retv);
  //lbi_print_stack("leave", th, th->hiber_thread_cx.rsp, stack_base);
  th->hiber_thread_cx.rsp -= stack_base;
  
  // copy out
  {
    LB_DG("sus", "switch-copy-out: ", LB_U(th), "\n");
    
    /*
      here we don't need to do anything to account for the "red
      zone". that's because the leaf function will always be
      lbi_context_switch which doesn't make any use of the "red zone".
    */
    uintptr_t rsp = (th->hiber_thread_cx.rsp + stack_base);
    LB_PV(rsp);
    
    uintptr_t rem = th->hiber_stack_len = (stack_base - rsp);
    LB_PV(rem);
    
    th->hiber_page_list = NULL;
    
    void do_amt(uintptr_t amt) {
      lbi_thread_page_t* tp = lbi_switch_page_obtain(sw);
      tp->next = th->hiber_page_list;
      th->hiber_page_list = tp;
      
      LB_PV(tp);
      LB_PV((tp->data + (page_capacity - amt)));
      LB_PV(rsp);
      LB_PV(amt);
      lb_memcpy((tp->data + (page_capacity - amt)), ((void*)(rsp)), amt);
      
      rsp += amt;
      
      rem -= amt;
    }
    
    uintptr_t mod = rem;
    
    while (mod >= page_capacity) {
      mod -= page_capacity;
    }
    
    if (mod > 0) {
      do_amt(mod);
    }
    
    while (rem > 0) {
      do_amt(page_capacity);
    }
    
    LB_ASSURE((rem == 0));
  }
  
  return retv;
}

/*
  event loop. this should only ever be invoked once, from "main". the
  event loop returns when there are no more runnable or I/O blocked
  threads. the improver is run after all runnable threads, and it may
  be run again if it releases threads to the runnable state and so
  forth, with I/O polling only being entered when there is no more
  progress to be made.
*/
static void lb_switch_event_loop(lb_switch_t* sw, bool (*proc_improver)(void*), void* user)
{
  while (true) {
    /*
      run runnables and improver
    */
    {
      while (sw->runnable_list) {
        LB_TR;
        /*
          run all runnables
        */
        {
          lb_thread_t* th;
          
          while ((th = sw->runnable_list)) {
            sw->runnable_list = th->runnable_next;
            
            if (!(th->hiber_page_list)) {
              LB_ALLOC_FREE(th, sw->ac);
              continue;
            }
            
            LB_PV(th);
            
            LB_ASSURE((th->runnable));
            th->runnable = false;
            
            sw->current = th;
            LB_AV(0, "entering thread");
            lbi_switch_load_exec_save(sw, th, th->runnable_retv);
            LB_AV(0, "leaving thread");
            sw->current = NULL;
            
            if (sw->destruct_me) {
              sw->destruct_me = false;
              LB_PV(th);
              lbi_switch_destruct_thread(sw, th);
            }
          }
          LB_TR;
        }
        LB_TR;
        /*
          run the "improver"
        */
        {
          if (proc_improver) {
            while (proc_improver(user));
          }
        }
        LB_TR;
      }
    }
    
    // check if there are any registered epoll triggers
    {
      if (sw->epoll_nr == 0) {
        /*
          oops, there aren't any. this means we would block forever if
          we entered epoll. let's get out of here.
        */
        LB_TR;
        return;
      }
    }
    
    // wait for epoll triggers and make the threads runnable
    {
      lbt_epoll_event_t events[LB_SWITCH_SIMULTANEOUS_EVENTS];
      
      uintptr_t amt;
      
      LB_TR;
      amt = LBT_OK(lbt_epoll_wait(sw->epoll_fd, events, LB_ARRLEN(events), -1U));
      LB_ASSURE((amt <= LB_ARRLEN(events)));
      LB_PV(amt);
      
      for (uintptr_t i = 0; i < amt; i++) {
        lb_thread_t* th = ((lb_thread_t*)(events[i].user));
        LB_PV(th);
        
        lbi_switch_epoll_disable(th);
        
        lbi_switch_add_runnable(sw, th, NULL);
      }
    }
  }
}

/*
  context switches to the event loop.
*/
static void lbi_switch_event_loop_switch_to(lb_thread_t* th)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;
  
  lb_context_yield((&(th->u.x.cs)), NULL);
}

/*
  suspends the current thread until it is woken up by disturb.
*/
static void lb_switch_slumber(lb_thread_t* th)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;
  
  th->slumber_enabled = true;
  
  lbi_switch_event_loop_switch_to(th);
}

static void lb_switch_disturb_by_switch(lb_switch_t* sw, lb_thread_t* th_target)
{
  LB_ASSURE((th_target->sw == sw));
  
  if (th_target->slumber_enabled) {
    th_target->slumber_enabled = false;
    
    lbi_switch_add_runnable(sw, th_target, NULL);
  }
}

/*
  wakes the given thread if it is in slumber. harmless if it isn't.
*/
static void lb_switch_disturb(lb_thread_t* th, lb_thread_t* th_target)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;
  
  lb_switch_disturb_by_switch(th->sw, th_target);
}

/*
  suspends the current thread until one of the given events is met by
  the given file descriptor. the file descriptor must be unique! use
  dup if the same underlying resource must be waited on by different
  threads.
*/
static void lb_switch_epoll_wait(lb_thread_t* th, uintptr_t fd, uint32_t events)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;

  LB_PV(th);
  LB_PV(fd);
  LB_PV(events);
  
  LB_ASSURE(!(th->epoll_enabled));
  th->epoll_enabled = true;
  th->epoll_fd = fd;
  
  {
    lbt_epoll_event_t event;
    LB_BZERO(event);
    event.events = events;
    event.user = th;
    LB_DG("susus", "epoll_ctl ADD th ", LB_U(th), " fd ", th->epoll_fd, "\n");
    LB_ASSURE_EQZ(lbt_epoll_ctl(th->sw->epoll_fd, lbt_EPOLL_CTL_ADD, fd, &event));
    th->sw->epoll_nr++;
  }
  
  lbi_switch_event_loop_switch_to(th);
}

/*
  adds a cleanup routine for the current thread
*/
static void lb_switch_push_cleanup(lb_thread_t* th, void (*proc)(lb_thread_t*, void*, void*, void*), void* user_a, void* user_b, void* user_c)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;
  
  LB_ASSURE((th->cleanup_stack_len < LB_SWITCH_CLEANUP_LIMIT));
  
  LB_CLONE(cl, (th->cleanup_stack_arr[((th->cleanup_stack_len)++)]));
  cl->proc = proc;
  cl->user_a = user_a;
  cl->user_b = user_b;
  cl->user_c = user_c;
}

#define LB_SWITCH_PUSH_CLEANUP_VARIANT_0(s)                             \
  static void lb_switch_push_cleanup_##s(lb_thread_t* th, void (*proc)(lb_thread_t*)) \
  {                                                                     \
    lb_switch_push_cleanup(th, ((lb_switch_cleanup_proc_t)(proc)), NULL, NULL, NULL); \
  }

#define LB_SWITCH_PUSH_CLEANUP_VARIANT_1(s, a)                          \
  static void lb_switch_push_cleanup_##s(lb_thread_t* th, void (*proc)(lb_thread_t*, a), a user_a) \
  {                                                                     \
    LB_ASSURE((sizeof(a) == sizeof(uintptr_t)));                        \
    lb_switch_push_cleanup(th, ((lb_switch_cleanup_proc_t)(proc)), ((void*)(user_a)), NULL, NULL); \
  }

#define LB_SWITCH_PUSH_CLEANUP_VARIANT_2(s, a, b)                       \
  static void lb_switch_push_cleanup_##s(lb_thread_t* th, void (*proc)(lb_thread_t*, a, b), a user_a, b user_b) \
  {                                                                     \
    LB_ASSURE((sizeof(a) == sizeof(uintptr_t)));                        \
    LB_ASSURE((sizeof(b) == sizeof(uintptr_t)));                        \
    lb_switch_push_cleanup(th, ((lb_switch_cleanup_proc_t)(proc)), ((void*)(user_a)), ((void*)(user_b)), NULL); \
  }

#define LB_SWITCH_PUSH_CLEANUP_VARIANT_3(s, a, b, c)                    \
  static void lb_switch_push_cleanup_##s(lb_thread_t* th, void (*proc)(lb_thread_t*, a, b, c), a user_a, b user_b, c user_c) \
  {                                                                     \
    LB_ASSURE((sizeof(a) == sizeof(uintptr_t)));                        \
    LB_ASSURE((sizeof(b) == sizeof(uintptr_t)));                        \
    LB_ASSURE((sizeof(c) == sizeof(uintptr_t)));                        \
    lb_switch_push_cleanup(th, ((lb_switch_cleanup_proc_t)(proc)), ((void*)(user_a)), ((void*)(user_b)), ((void*)(user_c))); \
  }

LB_SWITCH_PUSH_CLEANUP_VARIANT_3(lbi_free, lb_alloc_t*, void*, uintptr_t);

static void lbi_switch_push_cleanup_lbi_free_proc(lb_thread_t* th LB_UNUSED, lb_alloc_t* ac, void* ob, uintptr_t sz)
{
  lb_alloc_free(ac, ob, sz);
}

static void lb_switch_push_cleanup_free(lb_thread_t* th, lb_alloc_t* ac, void* ob, uintptr_t sz)
{
  lb_switch_push_cleanup_lbi_free(th, lbi_switch_push_cleanup_lbi_free_proc, ac, ob, sz);
}

/*
  pops a cleanup routine for the current thread
*/
static void lb_switch_pull_cleanup(lb_thread_t* th)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;
  
  LB_ASSURE((((th->cleanup_stack_len)--) > 0));
}

/*
  destructs another thread or the current thread.
  
  this is a bit tricky. other threads can be reaped directly, but the
  only way to reap the current thread is to set up destruct_me and
  context switch to the event loop. however, the context switch must
  be done -last- to avoid simply dropping other operations that would
  have taken place had the current thread been able to return from
  destruct_thread (in particular, the first destruct_thread call might
  not have been for the current thread but for some other thread whose
  cleanup handler triggered destructing the current thread so that the
  current thread's destruct ends up sandwiched in the stack).
  
  so, we keep track of the destruct nesting, and when it gets back
  down to zero we reap the current thread if necessary. of course, all
  of the code runs in the current thread from the start, it just may
  not have initially been targeting the current thread.
  
  the payoff to doing it this way, of course, is that a strong
  guarantee is exported to the programmer: regardless how intricate
  nested destructing of threads gets, all the destructing and cleanup
  that should happen happens, just as if it were being done by an
  anonymous background thread.
*/
static void lb_switch_destruct_thread(lb_thread_t* th, lb_thread_t* th_target)
{
  LBI_SWITCH_CURRENT_THREAD_ONLY;
  LBI_SWITCH_SAME_SWITCH_ONLY;
  
  lb_switch_t* sw = th->sw;
  
  LB_ASSURE(((th_target->sw) == sw));
  
  if (((sw->destruct_nesting)++) == 0) {
    LB_ASSURE(!(sw->destruct_me));
  }
  
  LB_ASSURE(!(th_target->destruct_enabled));
  th_target->destruct_enabled = true;
  LB_PV(th_target);
  
  /*
    take the thread out of epoll
  */
  if (th_target->epoll_enabled) {
    lbi_switch_epoll_disable(th_target);
  }
  
  /*
    run the cleanup handlers.
  */
  {
    for (uintptr_t i = th_target->cleanup_stack_len; (i--) > 0;) {
      LB_CLONE(cl, (th_target->cleanup_stack_arr[i]));
      cl->proc(th, cl->user_a, cl->user_b, cl->user_c);
    }
  }
  
  if (th_target == sw->current) {
    /*
      since this is a self destruct, we can't complete it ourselves so
      we need a bit of assistance from the event loop.
    */
    LB_ASSURE(!(sw->destruct_me));
    sw->destruct_me = true;
  } else {
    /*
      just some other thread. it's history (unless it has resurrect
      enabled).
    */
    lbi_switch_destruct_thread(sw, th_target);
  }
  
  if ((--(sw->destruct_nesting)) == 0) {
    if (sw->destruct_me) {
      lbi_switch_event_loop_switch_to(th);
    }
  }
}

typedef void (*lbi_switch_resurrect_me_thread_proc)(lb_thread_t*);
LB_SWITCH_PUSH_CLEANUP_VARIANT_1(_lbi_switch_resurrect_me_thread_proc, lbi_switch_resurrect_me_thread_proc);

static void lbi_switch_resurrect_me_cleanup_proc(lb_thread_t* th, void (*proc)(lb_thread_t*))
{
  lb_switch_create_thread(th->sw, ((void (*)(lb_thread_t*, void*))(proc)), NULL);
}

static void lb_switch_resurrect_me(lb_thread_t* th, void (*proc)(lb_thread_t*))
{
  lb_switch_push_cleanup__lbi_switch_resurrect_me_thread_proc(th, lbi_switch_resurrect_me_cleanup_proc, proc);
}

static void lbi_switch_assert_failed(lb_thread_t* th, char const* str)
{
  lbi_assure_write_string(str);
  
  lb_switch_destruct_thread(th, th);
}

#define LB_SWITCH_ASSURE(expr) { ((void)("LB_SWITCH_ASSURE")); if (!(expr)) { lbi_switch_assert_failed(th, LBI_ASSURE_GLOB("not_fatal", #expr)); } }

#define LB_SWITCH_ASSURE_LBT_OK(expr) ({ ((void)("LBT_OK")); intptr_t LB_SWITCH_ASSURE_LBT_OK__A; if (!((LB_SWITCH_ASSURE_LBT_OK__A = (LB_CHECK_TYPE(intptr_t, (expr)))) >= 0)) { lbi_switch_assert_failed(th, LBI_ASSURE_GLOB("not_fatal", #expr)); }; LB_UI(LB_SWITCH_ASSURE_LBT_OK__A); })
