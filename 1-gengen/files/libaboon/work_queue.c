/*
  libaboon/queue.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_work_queue_t)
{
  lb_alloc_t* ac;
  
  lb_queue_t* qu_work;
  lb_stack_t* sk_wait;
};

static lb_work_queue_t* lb_work_queue_create(lb_alloc_t* ac)
{
  LB_ALLOC_DECL(lb_work_queue_t, wq, ac);
  
  wq->ac = ac;
  
  wq->qu_work = lb_queue_create(ac);
  wq->sk_wait = lb_stack_create(ac);
  
  return wq;
}

static void lb_work_queue_delete(lb_work_queue_t* wq)
{
  lb_queue_delete(wq->qu_work, wq->ac);
  
  lb_stack_delete(wq->sk_wait);
  
  LB_ALLOC_FREE(wq, wq->ac);
}

static bool lb_work_queue_sense(lb_work_queue_t* wq)
{
  return lb_queue_sense(wq->qu_work);
}

static void lb_work_queue_submit(lb_thread_t* th, lb_work_queue_t* wq, void* work)
{
  lb_queue_push(wq->qu_work, work);
  
  /*
    kick exactly one waiting thread (if any).
  */
  if (lb_stack_sense(wq->sk_wait)) {
    lb_thread_t* th_target = ((lb_thread_t*)(lb_stack_pull(wq->sk_wait)));
    lb_switch_disturb(th, th_target);
  }
}

static void lb_work_queue_submit_by_switch(lb_switch_t* sw, lb_work_queue_t* wq, void* work)
{
  lb_queue_push(wq->qu_work, work);
  
  /*
    kick exactly one waiting thread (if any).
  */
  if (lb_stack_sense(wq->sk_wait)) {
    lb_thread_t* th_target = ((lb_thread_t*)(lb_stack_pull(wq->sk_wait)));
    lb_switch_disturb_by_switch(sw, th_target);
  }
}

static void lb_work_queue_resubmit(lb_thread_t* th, lb_work_queue_t* wq, void* work)
{
  /*
    we must push to the front of the queue, which is not directly
    supported. for now, just reach through to the queue's output stack
    - in the future all the stack/queue stuff may be rewritten to
    dequeues anyway.
  */
  lb_stack_push(wq->qu_work->sk_out, work);
  
  /*
    kick exactly one waiting thread (if any).
  */
  if (lb_stack_sense(wq->sk_wait)) {
    lb_thread_t* th_target = ((lb_thread_t*)(lb_stack_pull(wq->sk_wait)));
    lb_switch_disturb(th, th_target);
  }
}

LB_SWITCH_PUSH_CLEANUP_VARIANT_2(_lb_work_queue_t_void_p, lb_work_queue_t*, void*);

static void lb_work_queue_push_cleanup_resubmit(lb_thread_t* th, lb_work_queue_t* wq, void* user)
{
  lb_switch_push_cleanup__lb_work_queue_t_void_p(th, lb_work_queue_resubmit, wq, user);
}

static void lbi_work_queue_obtain_cleanup_proc(lb_thread_t* th, lb_work_queue_t* wq)
{
  lb_stack_delete_all(wq->sk_wait, th);
}

LB_SWITCH_PUSH_CLEANUP_VARIANT_1(_lb_work_queue_t, lb_work_queue_t*);

static void* lb_work_queue_obtain(lb_thread_t* th, lb_work_queue_t* wq)
{
  while (true) {
    if (lb_queue_sense(wq->qu_work)) {
      void* retv = lb_queue_pull(wq->qu_work);
      return retv;
    }
    
    lb_stack_push(wq->sk_wait, th);
    
    lb_switch_push_cleanup__lb_work_queue_t(th, lbi_work_queue_obtain_cleanup_proc, wq);
    lb_switch_slumber(th);
    lb_switch_pull_cleanup(th);
  }
}

static void* lb_work_queue_obtain_nonblocking(lb_work_queue_t* wq)
{
  void* retv = lb_queue_pull(wq->qu_work);
  return retv;
}
