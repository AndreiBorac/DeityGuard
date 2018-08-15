/*
  libaboon/token_bucket.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_token_bucket_t)
{
  uintptr_t amt;
  uintptr_t lim;
  
  lb_queue_t* qu_wait;
  
  uintptr_t trickle_count;
  uintptr_t trickle_every;
};

static lb_token_bucket_t* lb_token_bucket_create(lb_alloc_t* ac, uintptr_t lim, uintptr_t trickle_every)
{
  LB_ALLOC_DECL(lb_token_bucket_t, tb, ac);
  
  tb->amt = 0;
  tb->lim = lim;
  tb->qu_wait = lb_queue_create(ac);
  
  tb->trickle_count = 0;
  tb->trickle_every = trickle_every;
  
  return tb;
}

static void lb_token_bucket_delete(lb_token_bucket_t* tb, lb_alloc_t* ac)
{
  lb_queue_delete(tb->qu_wait, ac);
  
  LB_ALLOC_FREE(tb, ac);
}

static void lb_token_bucket_submit_by_switch(lb_switch_t* sw, lb_token_bucket_t* tb, uintptr_t amt)
{
  tb->amt = LB_MIN((tb->amt + amt), tb->lim);
  
  /*
    here we just wake everyone who is waiting indiscriminately. this
    should be optimized by queuing the expected number of tokens along
    with each thread and only wake as many threads as can run.
  */
  while (lb_queue_sense(tb->qu_wait)) {
    lb_switch_disturb_by_switch(sw, ((lb_thread_t*)(lb_queue_pull(tb->qu_wait))));
  }
}

static void lb_token_bucket_submit(lb_thread_t* th, lb_token_bucket_t* tb, uintptr_t amt)
{
  lb_token_bucket_submit_by_switch(th->sw, tb, amt);
}

static void lb_token_bucket_submit_trickle_by_switch(lb_switch_t* sw, lb_token_bucket_t* tb)
{
  if ((++(tb->trickle_count)) >= tb->trickle_every) {
    tb->trickle_count = 0;
    lb_token_bucket_submit_by_switch(sw, tb, 1);
  }
}

static void lbi_token_bucket_obtain_cleanup_proc(lb_thread_t* th, lb_token_bucket_t* tb)
{
  lb_queue_delete_all(tb->qu_wait, th);
}

LB_SWITCH_PUSH_CLEANUP_VARIANT_1(_lb_token_bucket_t, lb_token_bucket_t*);

static void lb_token_bucket_obtain(lb_thread_t* th, lb_token_bucket_t* tb, uintptr_t amt)
{
  while (tb->amt < amt) {
    lb_queue_push(tb->qu_wait, th);
    
    lb_switch_push_cleanup__lb_token_bucket_t(th, lbi_token_bucket_obtain_cleanup_proc, tb);
    lb_switch_slumber(th);
    lb_switch_pull_cleanup(th);
  }
  
  tb->amt -= amt;
}
