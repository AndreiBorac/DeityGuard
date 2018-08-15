/*
  libaboon/queue.c
  copyright (c) 2017 by andrei borac
*/

LB_TYPEBOTH(lb_queue_t)
{
  lb_stack_t* sk_inp;
  lb_stack_t* sk_out;
};

static lb_queue_t* lb_queue_create(lb_alloc_t* ac)
{
  LB_ALLOC_DECL(lb_queue_t, qu, ac);
  
  qu->sk_inp = lb_stack_create(ac);
  qu->sk_out = lb_stack_create(ac);
  
  return qu;
}

static void lb_queue_delete(lb_queue_t* qu, lb_alloc_t* ac)
{
  lb_stack_delete(qu->sk_inp);
  lb_stack_delete(qu->sk_out);
  
  LB_ALLOC_FREE(qu, ac);
}

static LB_INLINE uintptr_t lb_queue_size(lb_queue_t* qu)
{
  return (lb_stack_size(qu->sk_inp) + lb_stack_size(qu->sk_out));
}

static LB_INLINE bool lb_queue_empty(lb_queue_t* qu)
{
  return (lb_queue_size(qu) == 0);
}

static LB_INLINE bool lb_queue_sense(lb_queue_t* qu)
{
  return (lb_queue_size(qu) > 0);
}

static void lb_queue_push(lb_queue_t* qu, void* user)
{
  lb_stack_push(qu->sk_inp, user);
}

static void* lb_queue_pull(lb_queue_t* qu)
{
  if (lb_stack_empty(qu->sk_out)) {
    uintptr_t len = lb_stack_size(qu->sk_inp);
    void* elm[len];
    lb_stack_pull_many(qu->sk_inp, elm, len);
    lb_stack_push_many(qu->sk_out, elm, len);
    
    if (lb_stack_empty(qu->sk_out)) {
      LB_ILLEGAL;
    }
  }
  
  return lb_stack_pull(qu->sk_out);
}

static void lb_queue_push_many(lb_queue_t* qu, void* const* user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  for (uintptr_t i = 0; i < size; i++) {
    lb_queue_push(qu, user[i]);
  }
}

static void lb_queue_push_many_non_null(lb_queue_t* qu, void* const* user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  for (uintptr_t i = 0; i < size; i++) {
    if (user[i] != NULL) {
      lb_queue_push(qu, user[i]);
    }
  }
}

static void lb_queue_pull_many(lb_queue_t* qu, void** user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  for (uintptr_t i = 0; i < size; i++) {
    user[i] = lb_queue_pull(qu);
    LB_PV(user[i]);
  }
}

static void lb_queue_delete_all(lb_queue_t* qu, void* bad)
{
  lb_stack_delete_all(qu->sk_inp, bad);
  lb_stack_delete_all(qu->sk_out, bad);
}
