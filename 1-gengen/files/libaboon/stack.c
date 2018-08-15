/*
  libaboon/stack.c
  copyright (c) 2017 by andrei borac
*/

#ifndef LB_STACK_GROUP_LENGTH
#define LB_STACK_GROUP_LENGTH (16 - 1)
#endif

LB_TYPEDECL(lb_stack_group_t);
LB_TYPEDEFN(lb_stack_group_t)
{
  lb_stack_group_t* next;
  void*             user[LB_STACK_GROUP_LENGTH];
};

LB_TYPEBOTH(lb_stack_t)
{
  lb_alloc_t* ac;
  lb_alloc_direct_t ad;
  
  uintptr_t len;
  
  lb_stack_group_t* head;
  uintptr_t         head_used;
};

static lb_stack_t* lb_stack_create(lb_alloc_t* ac)
{
  LB_ALLOC_DECL(lb_stack_t, sk, ac);
  
  sk->ac = ac;
  sk->ad = lb_alloc_direct(ac, sizeof(lb_stack_group_t));
  
  sk->len = 0;
  
  sk->head = NULL;
  sk->head_used = LB_STACK_GROUP_LENGTH;
  
  return sk;
}

static void lb_stack_delete(lb_stack_t* sk)
{
  lb_stack_group_t* sg = sk->head;
  
  while (sg != NULL) {
    lb_stack_group_t* sg_next = sg->next;
    LB_ALLOC_FREE(sg, sk->ac);
    sg = sg_next;
  }
  
  LB_ALLOC_FREE(sk, sk->ac);
}

static LB_INLINE uintptr_t lb_stack_size(lb_stack_t* sk)
{
  return sk->len;
}

static LB_INLINE bool lb_stack_empty(lb_stack_t* sk)
{
  return (sk->len == 0);
}

static LB_INLINE bool lb_stack_sense(lb_stack_t* sk)
{
  return (sk->len > 0);
}

static void lb_stack_push(lb_stack_t* sk, void* user)
{
  if (sk->head_used < LB_STACK_GROUP_LENGTH) {
    sk->len++;
    sk->head->user[(sk->head_used)++] = user;
  } else {
    lb_stack_group_t* sg = ((lb_stack_group_t*)(lb_alloc_direct_alloc(sk->ad, sizeof(lb_stack_group_t), sk->ac)));
    sg->next = sk->head;
    sk->head = sg;
    sk->head_used = 0;
    
    return lb_stack_push(sk, user);
  }
}

static void* lb_stack_pull(lb_stack_t* sk)
{
  if (sk->head_used > 0) {
    LB_ASSURE_GTZ((sk->len--));
    return sk->head->user[--(sk->head_used)];
  } else {
    lb_stack_group_t* head_next = sk->head->next;
    lb_alloc_direct_free(sk->ad, sk->head);
    sk->head = head_next;
    sk->head_used = LB_STACK_GROUP_LENGTH;
    
    return lb_stack_pull(sk);
  }
}

static void lb_stack_push_many(lb_stack_t* sk, void* const* user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  for (uintptr_t i = 0; i < size; i++) {
    lb_stack_push(sk, user[i]);
  }
}

static void lb_stack_push_many_reverse(lb_stack_t* sk, void* const* user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  while (size > 0) {
    void* const uptr = user[--size];
    LB_PV(uptr);
    lb_stack_push(sk, uptr);
  }
}

static void lb_stack_push_many_non_null(lb_stack_t* sk, void* const* user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  for (uintptr_t i = 0; i < size; i++) {
    if (user[i] != NULL) {
      lb_stack_push(sk, user[i]);
    }
  }
}

static void lb_stack_pull_many(lb_stack_t* sk, void** user, uintptr_t size)
{
  /*
    TODO: optimize with chunked implementation
  */
  
  for (uintptr_t i = 0; i < size; i++) {
    user[i] = lb_stack_pull(sk);
    LB_PV(user[i]);
  }
}

static void lb_stack_delete_all(lb_stack_t* sk, void* bad)
{
  uintptr_t siz = lb_stack_size(sk);
  void* arr[siz];
  lb_stack_pull_many(sk, arr, siz);
  
  uintptr_t len = 0;
  
  for (uintptr_t i = 0; i < siz; i++) {
    if (arr[i] != bad) {
      arr[len++] = arr[i];
    }
  }
  
  lb_stack_push_many_reverse(sk, arr, len);
}
