/*
  libaboon/linux.c
  copyright (c) 2017 by andrei borac
*/

static intptr_t lbti_exit_group(uintptr_t code)
{
  return lb_syscall_1(lbt_SYS_exit_group, code);
}

static intptr_t lbti_brk(uintptr_t brk)
{
  return lb_syscall_1(lbt_SYS_brk, brk);
}

static intptr_t lbti_close(uintptr_t fd)
{
  return lb_syscall_1(lbt_SYS_close, fd);
}

static intptr_t lbti_read(uintptr_t fd, void* buf, uintptr_t len)
{
  return lb_syscall_3(lbt_SYS_read, fd, LB_U(buf), len);
}

static intptr_t lbti_write(uintptr_t fd, void const* buf, uintptr_t len)
{
  return lb_syscall_3(lbt_SYS_write, fd, LB_U(buf), len);
}

static intptr_t lbti_pread64(uintptr_t fd, void* buf, uintptr_t len, uint64_t off)
{
#ifdef LB_ARCH_X86_64
  return lb_syscall_4(lbt_SYS_pread64, fd, LB_U(buf), len, off);
#endif
  
#ifdef LB_ARCH_ARM_32
  return lb_syscall_6(lbt_SYS_pread64, fd, LB_U(buf), len, 0, ((uintptr_t)(off)), ((uintptr_t)(off >> 32)));
#endif
}

static intptr_t lbti_pwrite64(uintptr_t fd, void const* buf, uintptr_t len, uint64_t off)
{
#ifdef LB_ARCH_X86_64
  return lb_syscall_4(lbt_SYS_pwrite64, fd, LB_U(buf), len, off);
#endif
  
#ifdef LB_ARCH_ARM_32
  return lb_syscall_6(lbt_SYS_pwrite64, fd, LB_U(buf), len, 0, ((uintptr_t)(off)), ((uintptr_t)(off >> 32)));
#endif
}

static intptr_t lbti_dup(uintptr_t fd)
{
  return lb_syscall_1(lbt_SYS_dup, fd);
}

static intptr_t lbti_fcntl(uintptr_t fd, uintptr_t cmd, uintptr_t arg)
{
  return lb_syscall_3(lbt_SYS_fcntl, fd, cmd, arg);
}

typedef struct
{
  uint8_t opaque[lbt_sizeof_stat];
}
LB_PACKED lbt_stat_t;

static intptr_t lbti_stat(char const* path, lbt_stat_t* stat)
{
  return lb_syscall_2(lbt_SYS_stat, LB_U(path), LB_U(stat));
}

static intptr_t lbti_lstat(char const* path, lbt_stat_t* stat)
{
  return lb_syscall_2(lbt_SYS_lstat, LB_U(path), LB_U(stat));
}

static intptr_t lbti_open(char const* path, uintptr_t flags, uintptr_t mode)
{
  return lb_syscall_3(lbt_SYS_open, LB_U(path), flags, mode);
}

static intptr_t lbti_chmod(char const* path, uintptr_t mode)
{
  return lb_syscall_2(lbt_SYS_chmod, LB_U(path), mode);
}

static intptr_t lbti_unlink(char const* path)
{
  return lb_syscall_1(lbt_SYS_unlink, LB_U(path));
}

static intptr_t lbti_socket(uintptr_t family, uintptr_t type, uintptr_t protocol)
{
  return lb_syscall_3(lbt_SYS_socket, family, type, protocol);
}

static intptr_t lbti_getsockopt(uintptr_t fd, uintptr_t level, uintptr_t optname, void* optval, uintptr_t optlen)
{
  return lb_syscall_5(lbt_SYS_getsockopt, fd, level, optname, LB_U(optval), optlen);
}

static intptr_t lbti_setsockopt(uintptr_t fd, uintptr_t level, uintptr_t optname, void const* optval, uintptr_t optlen)
{
  return lb_syscall_5(lbt_SYS_setsockopt, fd, level, optname, LB_U(optval), optlen);
}

typedef struct
{
  uint16_t family;
  char path[108];
}
LB_PACKED lbt_sockaddr_un_t;

typedef struct
{
  uint16_t family;
  uint16_t   port;
  uint32_t   host;
  char    padding[8];
}
LB_PACKED lbt_sockaddr_in_t;

typedef struct
{
  uint16_t family;
  uint16_t protocol;
  uint32_t if_index;
  uint16_t unk1;
  uint8_t  unk2;
  uint8_t  hw_alen;
  uint8_t  hw_addr[8];
}
LB_PACKED lbt_sockaddr_ll_t;

static intptr_t lbti_connect(uintptr_t fd, void const* sa, uintptr_t sa_len)
{
  return lb_syscall_3(lbt_SYS_connect, fd, LB_U(sa), sa_len);
}

static intptr_t lbti_bind(uintptr_t fd, void const* sa, uintptr_t sa_len)
{
  return lb_syscall_3(lbt_SYS_bind, fd, LB_U(sa), sa_len);
}

static intptr_t lbti_listen(uintptr_t fd, uintptr_t backlog)
{
  return lb_syscall_2(lbt_SYS_listen, fd, backlog);
}

static intptr_t lbti_accept(uintptr_t fd, void* sa, uintptr_t* sa_len)
{
  return lb_syscall_3(lbt_SYS_accept, fd, LB_U(sa), LB_U(sa_len));
}

static intptr_t lbti_epoll_create1(uintptr_t flags)
{
  return lb_syscall_1(lbt_SYS_epoll_create1, flags);
}

#ifdef LB_ARCH_X86_64

typedef struct
{
  uint32_t events;
  void* user;
}
LB_PACKED lbt_epoll_event_t;

#endif

#ifdef LB_ARCH_ARM_32

typedef struct
{
  uint32_t events;
  uint32_t pad1;
  void* user;
  uint32_t pad2;
}
LB_PACKED lbt_epoll_event_t;

#endif

static intptr_t lbti_epoll_ctl(uintptr_t epfd, uintptr_t op, uintptr_t fd, lbt_epoll_event_t* event)
{
  return lb_syscall_4(lbt_SYS_epoll_ctl, epfd, op, fd, LB_U(event));
}

static intptr_t lbti_epoll_wait(uintptr_t epfd, lbt_epoll_event_t* events, uintptr_t maxevents, uintptr_t timeout)
{
  return lb_syscall_4(lbt_SYS_epoll_wait, epfd, LB_U(events), maxevents, timeout);
}

typedef struct
{
  uintptr_t sec;
  uintptr_t nsec;
}
LB_PACKED lbt_timespec_t;

typedef struct
{
  lbt_timespec_t interval;
  lbt_timespec_t initial;
}
LB_PACKED lbt_itimerspec_t;

static intptr_t lbti_timerfd_create(uintptr_t clockid, uintptr_t flags)
{
  return lb_syscall_2(lbt_SYS_timerfd_create, clockid, flags);
}

static intptr_t lbti_timerfd_settime(uintptr_t fd, uintptr_t flags, lbt_itimerspec_t const* ts, lbt_itimerspec_t* old_ts)
{
  return lb_syscall_4(lbt_SYS_timerfd_settime, fd, flags, LB_U(ts), LB_U(old_ts));
}

static intptr_t lbti_eventfd2(uintptr_t initval, uintptr_t flags)
{
  return lb_syscall_2(lbt_SYS_eventfd2, initval, flags);
}

static intptr_t lbti_io_setup(uintptr_t nr, uintptr_t* ctx)
{
  return lb_syscall_2(lbt_SYS_io_setup, nr, LB_U(ctx));
}

LB_TYPEBOTH(lbt_iocb_t)
{
  uint64_t aio_data;
  uint32_t aio_key;
  uint32_t aio_reserved1;
  uint16_t aio_lio_opcode;
  uint16_t aio_reqprio;
  uint32_t aio_fildes;
  
  uint64_t aio_buf;
  uint64_t aio_nbytes;
  uint64_t aio_offset;
  
  uint64_t aio_reserved2;
  
  uint32_t aio_flags;
  
  uint32_t aio_eventfd;
};

static intptr_t lbti_io_submit(uintptr_t ctx, uintptr_t num, lbt_iocb_t** arr)
{
  return lb_syscall_3(lbt_SYS_io_submit, ctx, num, LB_U(arr));
}

LB_TYPEBOTH(lbt_io_event_t)
{
  uint64_t data;
  uint64_t obj;
  int64_t  res;
  int64_t  res2;
};

static intptr_t lbti_io_getevents(uintptr_t ctx, uintptr_t min_nr, uintptr_t max_nr, lbt_io_event_t* events, lbt_timespec_t *timeout)
{
  return lb_syscall_5(lbt_SYS_io_getevents, ctx, min_nr, max_nr, LB_U(events), LB_U(timeout));
}

static intptr_t lbti_rt_sigprocmask(uintptr_t how, uint64_t const* set_new, uint64_t* set_old, uintptr_t set_size)
{
  return lb_syscall_4(lbt_SYS_rt_sigprocmask, how, LB_U(set_new), LB_U(set_old), set_size);
}

#ifndef LB_LINUX_NO_MODULE_SUPPORT

static intptr_t lbti_finit_module(uintptr_t fd, char const* args, uintptr_t flags)
{
  return lb_syscall_3(lbt_SYS_finit_module, fd, LB_U(args), flags);
}

#endif

/*
  in parkour parlance, in/out means relative to the application.
*/

#ifdef LBT_PARKOUR

#define LBTI_PARKOUR_FD 3

static void lbti_parkour_record_Z_O_1(uintptr_t a)
{
  uintptr_t x[] = { a };
  lbti_write(LBTI_PARKOUR_FD, x, sizeof(x));
}

static void lbti_parkour_record_Z_O_2(uintptr_t a, uintptr_t b)
{
  uintptr_t x[] = { a, b };
  lbti_write(LBTI_PARKOUR_FD, x, sizeof(x));
}

static void lbti_parkour_record_Z_O_3(uintptr_t a, uintptr_t b, uintptr_t c)
{
  uintptr_t x[] = { a, b, c };
  lbti_write(LBTI_PARKOUR_FD, x, sizeof(x));
}

static void lbti_parkour_record_Z_O_4(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d)
{
  uintptr_t x[] = { a, b, c, d };
  lbti_write(LBTI_PARKOUR_FD, x, sizeof(x));
}

static void lbti_parkour_record_Z_O_5(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e)
{
  uintptr_t x[] = { a, b, c, d, e };
  lbti_write(LBTI_PARKOUR_FD, x, sizeof(x));
}

static void lbti_parkour_record_Z_O_6(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e, uintptr_t f)
{
  uintptr_t x[] = { a, b, c, d, e, f };
  lbti_write(LBTI_PARKOUR_FD, x, sizeof(x));
}

static void lbti_parkour_replay_Z_O_1(uintptr_t a)
{
  uintptr_t x[] = { a };
  uintptr_t y[] = { a };
  lbti_read(LBTI_PARKOUR_FD, y, sizeof(x));
  LB_ASSURE(lb_memcmp(x, y, sizeof(x)));
}

static void lbti_parkour_replay_Z_O_2(uintptr_t a, uintptr_t b)
{
  uintptr_t x[] = { a, b };
  uintptr_t y[] = { a, b };
  lbti_read(LBTI_PARKOUR_FD, y, sizeof(x));
  LB_ASSURE(lb_memcmp(x, y, sizeof(x)));
}

static void lbti_parkour_replay_Z_O_3(uintptr_t a, uintptr_t b, uintptr_t c)
{
  uintptr_t x[] = { a, b, c };
  uintptr_t y[] = { a, b, c };
  lbti_read(LBTI_PARKOUR_FD, y, sizeof(x));
  LB_ASSURE(lb_memcmp(x, y, sizeof(x)));
}

static void lbti_parkour_replay_Z_O_4(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d)
{
  uintptr_t x[] = { a, b, c, d };
  uintptr_t y[] = { a, b, c, d };
  lbti_read(LBTI_PARKOUR_FD, y, sizeof(x));
  LB_ASSURE(lb_memcmp(x, y, sizeof(x)));
}

static void lbti_parkour_replay_Z_O_5(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e)
{
  uintptr_t x[] = { a, b, c, d, e };
  uintptr_t y[] = { a, b, c, d, e };
  lbti_read(LBTI_PARKOUR_FD, y, sizeof(x));
  LB_ASSURE(lb_memcmp(x, y, sizeof(x)));
}

static void lbti_parkour_replay_Z_O_6(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d, uintptr_t e, uintptr_t f)
{
  uintptr_t x[] = { a, b, c, d, e, f };
  uintptr_t y[] = { a, b, c, d, e, f };
  lbti_read(LBTI_PARKOUR_FD, y, sizeof(x));
  LB_ASSURE(lb_memcmp(x, y, sizeof(x)));
}

static void lbti_parkour_record_Z_O_M(void const* x, uintptr_t l)
{
  if (x && (LB_IU(l) > 0)) {
    lbti_write(LBTI_PARKOUR_FD, x, l);
  }
}

static void lbti_parkour_replay_Z_O_M(void const* x, uintptr_t l)
{
  if (x && (LB_IU(l) > 0)) {
    unsigned char buf[l];
    lbti_read(LBTI_PARKOUR_FD, buf, l);
    LB_ASSURE(lb_memcmp(buf, x, l));
  }
}

static void lbti_parkour_record_Z_O_M_A(void const* x, uintptr_t z, uintptr_t n)
{
  if (x && (LB_IU(n) > 0)) {
    lbti_parkour_record_Z_O_M(x, (n * z));
  }
}

static void lbti_parkour_replay_Z_O_M_A(void const* x, uintptr_t z, uintptr_t n)
{
  if (x && (LB_IU(n) > 0)) {
    lbti_parkour_replay_Z_O_M(x, (n * z));
  }
}

static void lbti_parkour_record_Z_O_M_M_A(void const* const* x, uintptr_t z, uintptr_t n)
{
  if (x && (n > 0)) {
    lbti_parkour_record_Z_O_1(n);
    
    lbti_parkour_record_Z_O_M(x, (n * sizeof(void*)));
    
    for (uintptr_t i = 0; i < n; i++) {
      lbti_parkour_record_Z_O_M(x[i], z);
    }
  }
}

static void lbti_parkour_replay_Z_O_M_M_A(void const* const* x, uintptr_t z, uintptr_t n)
{
  if (n > 0) {
    lbti_parkour_replay_Z_O_1(n);
    
    lbti_parkour_replay_Z_O_M(x, (n * sizeof(void*)));
    
    for (uintptr_t i = 0; i < n; i++) {
      lbti_parkour_replay_Z_O_M(x[i], z);
    }
  }
}

static intptr_t lbti_parkour_record_Z_I(intptr_t v)
{
  lbti_write(LBTI_PARKOUR_FD, &v, sizeof(v));
  return v;
}

static intptr_t lbti_parkour_replay_Z_I(intptr_t v LB_UNUSED)
{
  intptr_t x;
  lbti_read(LBTI_PARKOUR_FD, &x, sizeof(x));
  return x;
}

static void lbti_parkour_record_Z_I_M(void* x, uintptr_t l)
{
  if (x && (LB_IU(l) > 0)) {
    lbti_write(LBTI_PARKOUR_FD, x, l);
  }
}

static void lbti_parkour_replay_Z_I_M(void* x, uintptr_t l)
{
  if (x && (LB_IU(l) > 0)) {
    lbti_read(LBTI_PARKOUR_FD, x, l);
  }
}

static void lbti_parkour_record_Z_I_M_A(void* x, uintptr_t z, uintptr_t n)
{
  if (x && (LB_IU(n) > 0)) {
    lbti_write(LBTI_PARKOUR_FD, x, (n * z));
  }
}

static void lbti_parkour_replay_Z_I_M_A(void* x, uintptr_t z, uintptr_t n)
{
  if (x && (LB_IU(n) > 0)) {
    lbti_read(LBTI_PARKOUR_FD, x, (n * z));
  }
}

#if   defined(LBT_PARKOUR_RECORD)
/* parkour record */
#define Z_O(...) LB_VA_NARGS_CALL(lbti_parkour_record_Z_O_, __VA_ARGS__)
#define Z_O_M(x, l)               lbti_parkour_record_Z_O_M((x), (l))
#define Z_O_M_A(x, z, n)          lbti_parkour_record_Z_O_M_A((x), (z), (n))
#define Z_O_M_M_A(x, z, n)        lbti_parkour_record_Z_O_M_M_A((x), (z), (n))
#define Z_I(v)                    lbti_parkour_record_Z_I((v))
#define Z_I_M(x, l)               lbti_parkour_record_Z_I_M((x), (l))
#define Z_I_M_A(x, z, n)          lbti_parkour_record_Z_I_M_A((x), (z), (n))
#elif defined(LBT_PARKOUR_REPLAY)
/* parkour replay */
#define Z_O(...) LB_VA_NARGS_CALL(lbti_parkour_replay_Z_O_, __VA_ARGS__)
#define Z_O_M(x, l)               lbti_parkour_replay_Z_O_M((x), (l))
#define Z_O_M_A(x, z, n)          lbti_parkour_replay_Z_O_M_A((x), (z), (n))
#define Z_O_M_M_A(x, z, n)        lbti_parkour_replay_Z_O_M_M_A((x), (z), (n))
#define Z_I(v)                    lbti_parkour_replay_Z_I(-1L)
#define Z_I_M(x, l)               lbti_parkour_replay_Z_I_M((x), (l))
#define Z_I_M_A(x, z, n)          lbti_parkour_replay_Z_I_M_A((x), (z), (n))
#else
#error "must define one of LBT_PARKOUR_RECORD or LBT_PARKOUR_REPLAY to use parkour"
#endif

#else

/* not parkour */
#define Z_O(...)           /* nothing */
#define Z_O_M(x, l)        /* nothing */
#define Z_O_M_A(x, z, n)   /* nothing */
#define Z_O_M_M_A(x, z, n) /* nothing */
#define Z_I(x)             (x)
#define Z_I_M(x, l)        /* nothing */
#define Z_I_M_A(x, z, n)   /* nothing */

#endif

#define Z_P(p) ((p) ? 1 : 0)
#define Z_O_M_S(x) Z_O_M(x, (lb_strlen(x) + 1))

static LB_INLINE intptr_t lbt_exit_group(uintptr_t code) { Z_O(lbt_SYS_exit_group, code); intptr_t retv = Z_I(lbti_exit_group(code)); return retv; }
static LB_INLINE intptr_t lbt_brk(uintptr_t brk) { Z_O(lbt_SYS_brk, brk); intptr_t retv = Z_I(lbti_brk(brk)); return retv; }
static LB_INLINE intptr_t lbt_close(uintptr_t fd) { Z_O(lbt_SYS_close, fd); intptr_t retv = Z_I(lbti_close(fd)); return retv; }
static LB_INLINE intptr_t lbt_read(uintptr_t fd, void* buf, uintptr_t len) { Z_O(lbt_SYS_read, fd, Z_P(buf), len); intptr_t retv = Z_I(lbti_read(fd, buf, len)); Z_I_M(buf, LB_UI(retv)); return retv; }
static LB_INLINE intptr_t lbt_write(uintptr_t fd, void const* buf, uintptr_t len) { Z_O(lbt_SYS_write, fd, Z_P(buf), len); Z_O_M(buf, len); intptr_t retv; if (fd == 2) { retv = lbti_write(fd, buf, len); retv = Z_I(retv); } else { retv = Z_I(lbti_write(fd, buf, len)); }; return retv; }
static LB_INLINE intptr_t lbt_pread64(uintptr_t fd, void* buf, uintptr_t len, uint64_t off) { Z_O(lbt_SYS_pread64, fd, Z_P(buf), len, off); intptr_t retv = Z_I(lbti_pread64(fd, buf, len, off)); Z_I_M(buf, LB_UI(retv)); return retv; }
static LB_INLINE intptr_t lbt_pwrite64(uintptr_t fd, void const* buf, uintptr_t len, uint64_t off) { Z_O(lbt_SYS_pwrite64, fd, Z_P(buf), len, off); Z_O_M(buf, len); intptr_t retv = Z_I(lbti_pwrite64(fd, buf, len, off)); return retv; }
static LB_INLINE intptr_t lbt_dup(uintptr_t fd) { Z_O(lbt_SYS_dup, fd); intptr_t retv = Z_I(lbti_dup(fd)); return retv; }
static LB_INLINE intptr_t lbt_fcntl(uintptr_t fd, uintptr_t cmd, uintptr_t arg) { Z_O(lbt_SYS_fcntl, fd, cmd, arg); intptr_t retv = Z_I(lbti_fcntl(fd, cmd, arg)); return retv; }
static LB_INLINE intptr_t lbt_stat(char const* path, lbt_stat_t* stat) { Z_O(lbt_SYS_stat, Z_P(path), Z_P(stat)); Z_O_M_S(path); intptr_t retv = Z_I(lbti_stat(path, stat)); Z_I_M(stat, sizeof(stat)); return retv; }
static LB_INLINE intptr_t lbt_lstat(char const* path, lbt_stat_t* stat) { Z_O(lbt_SYS_stat, Z_P(path), Z_P(stat)); Z_O_M_S(path); intptr_t retv = Z_I(lbti_lstat(path, stat)); Z_I_M(stat, sizeof(stat)); return retv; }
static LB_INLINE intptr_t lbt_open(char const* path, uintptr_t flags, uintptr_t mode) { Z_O(lbt_SYS_open, Z_P(path), flags, mode); Z_O_M_S(path); intptr_t retv = Z_I(lbti_open(path, flags, mode)); return retv; }
static LB_INLINE intptr_t lbt_chmod(char const* path, uintptr_t mode) { Z_O(lbt_SYS_chmod, Z_P(path), mode); Z_O_M_S(path); intptr_t retv = Z_I(lbti_chmod(path, mode)); return retv; }
static LB_INLINE intptr_t lbt_unlink(char const* path) { Z_O(lbt_SYS_unlink, Z_P(path)); Z_O_M_S(path); intptr_t retv = Z_I(lbti_unlink(path)); return retv; }
static LB_INLINE intptr_t lbt_socket(uintptr_t family, uintptr_t type, uintptr_t protocol) { Z_O(lbt_SYS_socket, family, type, protocol); intptr_t retv = Z_I(lbti_socket(family, type, protocol)); return retv; }
static LB_INLINE intptr_t lbt_getsockopt(uintptr_t fd, uintptr_t level, uintptr_t optname, void* optval, uintptr_t optlen) { Z_O(lbt_SYS_getsockopt, fd, level, optname, Z_P(optval), optlen); intptr_t retv = Z_I(lbti_getsockopt(fd, level, optname, optval, optlen)); Z_I_M(optval, optlen); return retv; }
static LB_INLINE intptr_t lbt_setsockopt(uintptr_t fd, uintptr_t level, uintptr_t optname, void const* optval, uintptr_t optlen) { Z_O(lbt_SYS_setsockopt, fd, level, optname, Z_P(optval), optlen); Z_O_M(optval, optlen); intptr_t retv = Z_I(lbti_setsockopt(fd, level, optname, optval, optlen)); return retv; }
static LB_INLINE intptr_t lbt_connect(uintptr_t fd, void const* sa, uintptr_t sa_len) { Z_O(lbt_SYS_connect, fd, Z_P(sa), sa_len); Z_O_M(sa, sa_len); intptr_t retv = Z_I(lbti_connect(fd, sa, sa_len)); return retv; }
static LB_INLINE intptr_t lbt_bind(uintptr_t fd, void const* sa, uintptr_t sa_len) { Z_O(lbt_SYS_bind, fd, Z_P(sa), sa_len); Z_O_M(sa, sa_len); intptr_t retv = Z_I(lbti_bind(fd, sa, sa_len)); return retv; }
static LB_INLINE intptr_t lbt_listen(uintptr_t fd, uintptr_t backlog) { Z_O(lbt_SYS_listen, fd, backlog); intptr_t retv = Z_I(lbti_listen(fd, backlog)); return retv; }
static LB_INLINE intptr_t lbt_accept(uintptr_t fd, void* sa, uintptr_t* sa_len) { Z_O(lbt_SYS_accept, fd, Z_P(sa), Z_P(sa_len)); intptr_t retv = Z_I(lbti_accept(fd, sa, sa_len)); if (sa) { Z_I_M(sa, (*sa_len)); }; return retv; }
static LB_INLINE intptr_t lbt_epoll_create1(uintptr_t flags) { Z_O(lbt_SYS_epoll_create1, flags); intptr_t retv = Z_I(lbti_epoll_create1(flags)); return retv; }
static LB_INLINE intptr_t lbt_epoll_ctl(uintptr_t epfd, uintptr_t op, uintptr_t fd, lbt_epoll_event_t* event) { Z_O(lbt_SYS_epoll_ctl, epfd, op, fd, Z_P(event)); Z_O_M(event, sizeof(*event)); intptr_t retv = lbti_epoll_ctl(epfd, op, fd, event); return retv; }
static LB_INLINE intptr_t lbt_epoll_wait(uintptr_t epfd, lbt_epoll_event_t* events, uintptr_t maxevents, uintptr_t timeout) { Z_O(lbt_SYS_epoll_wait, epfd, Z_P(events), maxevents, timeout); Z_O_M_A(events, sizeof(*events), maxevents); intptr_t retv = Z_I(lbti_epoll_wait(epfd, events, maxevents, timeout)); Z_I_M_A(events, sizeof(*events), LB_UI(retv)); return retv; }
static LB_INLINE intptr_t lbt_timerfd_create(uintptr_t clockid, uintptr_t flags) { Z_O(lbt_SYS_timerfd_create, clockid, flags); intptr_t retv = Z_I(lbti_timerfd_create(clockid, flags)); return retv; }
static LB_INLINE intptr_t lbt_timerfd_settime(uintptr_t fd, uintptr_t flags, lbt_itimerspec_t const* ts, lbt_itimerspec_t* old_ts) { Z_O(lbt_SYS_timerfd_settime, fd, flags, Z_P(ts), Z_P(old_ts)); Z_O_M(ts, sizeof(*ts)); intptr_t retv = Z_I(lbti_timerfd_settime(fd, flags, ts, old_ts)); Z_I_M(old_ts, sizeof(*old_ts)); return retv; }
static LB_INLINE intptr_t lbt_eventfd2(uintptr_t initval, uintptr_t flags) { Z_O(lbt_SYS_eventfd2, initval, flags); intptr_t retv = Z_I(lbti_eventfd2(initval, flags)); return retv; }
static LB_INLINE intptr_t lbt_io_setup(uintptr_t nr, uintptr_t* ctx) { Z_O(lbt_SYS_io_setup, nr, Z_P(ctx)); intptr_t retv = Z_I(lbti_io_setup(nr, ctx)); Z_I_M(ctx, sizeof(*ctx)); return retv; }
static LB_INLINE intptr_t lbt_io_submit(uintptr_t ctx, uintptr_t num, lbt_iocb_t** arr) { Z_O(lbt_SYS_io_submit, ctx, num, Z_P(arr)); Z_O_M_M_A(((void const* const*)(arr)), sizeof(lbt_iocb_t), num); intptr_t retv = Z_I(lbti_io_submit(ctx, num, arr)); return retv; }
static LB_INLINE intptr_t lbt_io_getevents(uintptr_t ctx, uintptr_t min_nr, uintptr_t max_nr, lbt_io_event_t* events, lbt_timespec_t *timeout) { Z_O(lbt_SYS_io_getevents, ctx, min_nr, max_nr, Z_P(events), Z_P(timeout)); Z_O_M(timeout, sizeof(*timeout)); intptr_t retv = Z_I(lbti_io_getevents(ctx, min_nr, max_nr, events, timeout)); Z_I_M_A(events, sizeof(*events), LB_UI(retv)); return retv; }
static LB_INLINE intptr_t lbt_rt_sigprocmask(uintptr_t how, uint64_t const* set_new, uint64_t* set_old, uintptr_t set_size) { Z_O(lbt_SYS_rt_sigprocmask, how, Z_P(set_new), Z_P(set_old), set_size); Z_O_M(set_new, sizeof(*set_new)); intptr_t retv = Z_I(lbti_rt_sigprocmask(how, set_new, set_old, set_size)); Z_I_M(set_old, sizeof(*set_old)); return retv; }
#ifndef LB_LINUX_NO_MODULE_SUPPORT
static LB_INLINE intptr_t lbt_finit_module(uintptr_t fd, char const* args, uintptr_t flags) { Z_O(lbt_SYS_finit_module, fd, Z_P(args), flags); Z_O_M_S(args); intptr_t retv = Z_I(lbti_finit_module(fd, args, flags)); return retv; }
#endif

#undef Z_P
#undef Z_O_M_S

#undef Z_O
#undef Z_O_M
#undef Z_O_M_A
#undef Z_O_M_M_A
#undef Z_I
#undef Z_I_M
#undef Z_I_M_A

#define LBT_OK(x) ({ ((void)("LBT_OK")); LB_UI(LB_ASSURE_GEZ(x)); })

static void lbt_exit_simple(uintptr_t code)
{
  lbti_exit_group(code);
  LB_ILLEGAL;
}

static intptr_t lbt_accept_simple(uintptr_t fd)
{
  return lbt_accept(fd, NULL, NULL);
}

static void lbt_block_signal_simple(uintptr_t signal)
{
  uint64_t v = (1U << (signal - 1));
  LBT_OK(lbti_rt_sigprocmask(lbt_SIG_BLOCK, (&v), NULL, sizeof(v)));
}

static void lbt_block_signal_simple_SIGPIPE(void)
{
  lbt_block_signal_simple(lbt_SIGPIPE);
}

static void lbt_unblock_signal_simple(uintptr_t signal)
{
  uint64_t v = (1U << (signal - 1));
  LBT_OK(lbti_rt_sigprocmask(lbt_SIG_UNBLOCK, (&v), NULL, sizeof(v)));
}

static void lbt_unblock_signal_simple_SIGPIPE(void)
{
  lbt_unblock_signal_simple(lbt_SIGPIPE);
}

typedef struct
{
  char name[lbt_IFNAMSIZ]; /* 16 */
  
  union {
    uint8_t   u8[(40-16)/1];
    uint16_t u16[(40-16)/2];
    uint32_t u32[(40-16)/4];
    uint64_t u64[(40-16)/8];
  } misc;
}
LB_PACKED lbt_ifreq_t;

static intptr_t lbt_ioctl_bypass(uintptr_t fd, uintptr_t cmd, uintptr_t arg)
{
  return lb_syscall_3(lbt_SYS_ioctl, fd, cmd, arg);
}

static intptr_t lbt_sendto_bypass(uintptr_t fd, void const* buf, uintptr_t len, uintptr_t flags, void const* sa, uintptr_t sa_len)
{
  return lb_syscall_6(lbt_SYS_sendto, fd, LB_U(buf), len, flags, LB_U(sa), sa_len);
}

static intptr_t lbt_recvfrom_bypass(uintptr_t fd, void const* buf, uintptr_t len, uintptr_t flags, void const* sa, uintptr_t sa_len)
{
  return lb_syscall_6(lbt_SYS_recvfrom, fd, LB_U(buf), len, flags, LB_U(sa), sa_len);
}

static intptr_t lbt_nanosleep_bypass(uintptr_t sec, uintptr_t nsec)
{
  lbt_timespec_t ts = { .sec = sec, .nsec = nsec };
  
  return lb_syscall_2(lbt_SYS_nanosleep, LB_U((&(ts))), LB_U(NULL));
}

static intptr_t lbt_sigtimedwait_simple_SIGPIPE_bypass(void)
{
  lbt_timespec_t ts = { .sec = 0, .nsec = 1 };
  
  uintptr_t v = (1U << (lbt_SIGPIPE - 1));
  
  return lb_syscall_4(lbt_SYS_rt_sigtimedwait, LB_U((&(v))), LB_U(NULL), LB_U((&(ts))), sizeof(v));
}

static intptr_t lbt_execve_bypass(char const* file, char const* const* argv, char const* const* envp)
{
  return lb_syscall_3(lbt_SYS_execve, LB_U(file), LB_U(argv), LB_U(envp));
}

static intptr_t lbt_mkdir_bypass(char const* path, uintptr_t mode)
{
  return lb_syscall_2(lbt_SYS_mkdir, LB_U(path), mode);
}

static intptr_t lbt_symlink_bypass(char const* trgt, char const* path)
{
  return lb_syscall_2(lbt_SYS_symlink, LB_U(trgt), LB_U(path));
}

static intptr_t lbt_mount_bypass(char const* src, char const* tgt, char const* typ, uintptr_t flags, void const* data)
{
  return lb_syscall_5(lbt_SYS_mount, LB_U(src), LB_U(tgt), LB_U(typ), flags, LB_U(data));
}

static intptr_t lbt_setuid_bypass(uintptr_t uid)
{
  uintptr_t sys_nr = lbt_SYS_setgid;
#ifdef LB_ARCH_ARM_32
  sys_nr = lbt_SYS_setuid32;
#endif
  return lb_syscall_1(sys_nr, uid);
}

static intptr_t lbt_setgid_bypass(uintptr_t gid)
{
  uintptr_t sys_nr = lbt_SYS_setgid;
#ifdef LB_ARCH_ARM_32
  sys_nr = lbt_SYS_setgid32;
#endif
  return lb_syscall_1(sys_nr, gid);
}

static intptr_t lbt_mlockall_bypass(uintptr_t flags)
{
  return lb_syscall_1(lbt_SYS_mlockall, flags);
}

static intptr_t lbt_lseek_bypass(uintptr_t fd, uintptr_t off, uintptr_t ori)
{
  return lb_syscall_3(lbt_SYS_lseek, fd, off, ori);
}

static intptr_t lbt_fork_bypass(void)
{
  return lb_syscall_0(lbt_SYS_fork);
}

static intptr_t lbt_wait_simple_bypass(uintptr_t pid)
{
  return lb_syscall_4(lbt_SYS_wait4, pid, 0, lbt_WNOHANG, 0);
}

static void lbt_reboot_simple_bypass(void)
{
  lb_syscall_3(lbt_SYS_reboot, 0xfee1dead, 672274793, 0x01234567);
  LB_ILLEGAL;
}
