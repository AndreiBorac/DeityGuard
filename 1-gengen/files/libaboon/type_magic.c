/*
  libaboon/type_magic.c
  copyright (c) 2017 by andrei borac
*/

#define lb_switch_create_thread_tm_0(sw, proc)                          \
  ({                                                                    \
    lb_switch_t* __tm_sw = (sw);                                        \
    void (*__tm_proc)(lb_thread_t*) = (proc);                           \
    void* __tm_user = NULL;                                             \
    lb_switch_create_thread(__tm_sw, ((void (*)(lb_thread_t*, void*))(__tm_proc)), ((void*)(__tm_user))); \
  })

#define lb_switch_create_thread_tm_1(sw, proc, user)                    \
  ({                                                                    \
    lb_switch_t* __tm_sw = (sw);                                        \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user)) = (proc);         \
    __typeof__(user) __tm_user = (user);                                \
    lb_switch_create_thread(__tm_sw, ((void (*)(lb_thread_t*, void*))(__tm_proc)), ((void*)(__tm_user))); \
  })

#define lb_switch_push_cleanup_tm_3(th, proc, user_a, user_b, user_c)   \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user_a), __typeof__(user_b), __typeof__(user_c)) = (proc); \
    lb_switch_push_cleanup((th), ((void (*)(lb_thread_t*, void*, void*, void*))(__tm_proc)), ((void*)(user_a)), ((void*)(user_b)), ((void*)(user_c))); \
  });

#define lb_switch_push_cleanup_tm_2(th, proc, user_a, user_b)           \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user_a), __typeof__(user_b)) = (proc); \
    lb_switch_push_cleanup((th), ((void (*)(lb_thread_t*, void*, void*, void*))(__tm_proc)), ((void*)(user_a)), ((void*)(user_b)), NULL); \
  });

#define lb_switch_push_cleanup_tm_1(th, proc, user_a)                   \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user_a)) = (proc);      \
    lb_switch_push_cleanup((th), ((void (*)(lb_thread_t*, void*, void*, void*))(__tm_proc)), ((void*)(user_a)), NULL, NULL); \
  });

#define lb_switch_push_cleanup_tm_0(th, proc)                           \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*)) = (proc); \
    lb_switch_push_cleanup((th), ((void (*)(lb_thread_t*, void*, void*, void*))(__tm_proc)), NULL, NULL, NULL); \
  });

#define lb_queue_pull_many_tm(t, v, l, qu, amt)                         \
  uintptr_t l = (amt);                                                  \
  t* v[l];                                                              \
  lb_queue_pull_many((qu), ((void**)(v)), l);                           \
  /* end */

#define lb_queue_pull_all_tm(t, v, l, qu)                               \
  lb_queue_pull_many_tm(t, v, l, qu, lb_queue_size(qu));                \
  /* end */

#define lb_queue_peek_all_tm(t, v, l, qu)                               \
  lb_queue_pull_many_tm(t, v, l, qu, lb_queue_size(qu));                \
  lb_queue_push_many((qu), ((void**)(v)), l);                           \
  /* end */

#define lb_stack_pull_many_tm(t, v, l, sk, amt)                         \
  uintptr_t l = (amt);                                                  \
  t* v[l];                                                              \
  lb_stack_pull_many((sk), ((void**)(v)), l);                           \
  /* end */

#define lb_stack_pull_all_tm(t, v, l, sk)                               \
  lb_stack_pull_many_tm(t, v, l, sk, lb_stack_size(sk));                \
  /* end */

#define lb_stack_peek_all_tm(t, v, l, sk)                               \
  lb_stack_pull_many_tm(t, v, l, sk, lb_stack_size(sk));                \
  lb_stack_push_many_reverse((sk), ((void**)(v)), l);                   \
  /* end */

#define lb_heartbeat_launch_tm_0(sw, ac, iv, qu, wq, proc)              \
  ({                                                                    \
    lb_switch_t* __tm_sw = (sw);                                        \
    lb_alloc_t* __tm_ac = (ac);                                         \
    uintptr_t __tm_iv = (iv);                                           \
    lb_queue_t* __tm_qu = (qu);                                         \
    lb_work_queue_t* __tm_wq = (wq);                                    \
    void (*__tm_proc)(lb_thread_t*, uint64_t) = (proc);                 \
    void* __tm_user = NULL;                                             \
    lb_heartbeat_launch(__tm_sw, __tm_ac, __tm_iv, __tm_qu, __tm_wq, ((void (*)(lb_thread_t*, uint64_t, void*))(__tm_proc)), ((void*)(__tm_user))); \
  })

#define lb_heartbeat_launch_tm_1(sw, ac, iv, qu, wq, proc, user)        \
  ({                                                                    \
    lb_switch_t* __tm_sw = (sw);                                        \
    lb_alloc_t* __tm_ac = (ac);                                         \
    uintptr_t __tm_iv = (iv);                                           \
    lb_queue_t* __tm_qu = (qu);                                         \
    lb_work_queue_t* __tm_wq = (wq);                                    \
    void (*__tm_proc)(lb_thread_t*, uint64_t, __typeof__(user)) = (proc); \
    __typeof__(user) __tm_user = (user);                                \
    lb_heartbeat_launch(__tm_sw, __tm_ac, __tm_iv, __tm_qu, __tm_wq, ((void (*)(lb_thread_t*, uint64_t, void*))(__tm_proc)), ((void*)(__tm_user))); \
  })
