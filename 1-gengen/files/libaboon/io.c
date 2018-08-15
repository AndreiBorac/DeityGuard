/*
  libaboon/io.c
  copyright (c) 2017 by andrei borac
*/

LB_SWITCH_PUSH_CLEANUP_VARIANT_1(lbi_close, uintptr_t);

static void lbi_io_cleanup_proc(lb_thread_t* th LB_UNUSED, uintptr_t fd)
{
  lbt_close(fd);
}

static void lb_io_push_cleanup_close_fd(lb_thread_t* th, uintptr_t fd)
{
  lb_switch_push_cleanup_lbi_close(th, lbi_io_cleanup_proc, fd);
}

static void lb_io_set_nonblocking(uintptr_t fd)
{
  uintptr_t flags;
  flags = LBT_OK(lbt_fcntl(fd, lbt_F_GETFL, 0));
  flags |= lbt_O_NONBLOCK;
  LB_ASSURE_EQZ(lbt_fcntl(fd, lbt_F_SETFL, flags));
  flags = LBT_OK(lbt_fcntl(fd, lbt_F_GETFL, 0));
  LB_ASSURE_NEZ((flags & lbt_O_NONBLOCK));
}

#define LBI_IO_TRYAGAIN ((retv == (-lbt_EAGAIN)) || (retv == (-lbt_EWOULDBLOCK)))

/*
  returns after reading/writing would be possible.
*/
#define LBI_IO_READ_OR_WRITE_WAIT_READY(read_or_write, epolldir)        \
  static void lb_io_##read_or_write##_wait_ready(lb_thread_t* th, uintptr_t fd) \
  {                                                                     \
    lb_switch_epoll_wait(th, fd, epolldir);                             \
  }

LBI_IO_READ_OR_WRITE_WAIT_READY(read,  lbt_EPOLLIN);
LBI_IO_READ_OR_WRITE_WAIT_READY(write, lbt_EPOLLOUT);

/*
  returns after reading/writing at least one byte. if an error is
  encountered, the thread is destructed.
*/
#define LBI_IO_READ_OR_WRITE(read_or_write, bufdecl, epolldir)          \
  static uintptr_t lb_io_##read_or_write(lb_thread_t* th, uintptr_t fd, void bufdecl* buf, uintptr_t len) \
  {                                                                     \
    /* doesn't make any sense to read or write zero bytes */            \
    LB_ASSURE((len > 0));                                               \
                                                                        \
    while (1) {                                                         \
      intptr_t retv = lbt_##read_or_write(fd, buf, len);                \
                                                                        \
      if (retv <= 0) {                                                  \
        if (LBI_IO_TRYAGAIN) {                                          \
          lb_switch_epoll_wait(th, fd, epolldir);                       \
          continue;                                                     \
        } else {                                                        \
          lb_switch_destruct_thread(th, th);                            \
        }                                                               \
      }                                                                 \
                                                                        \
      return LB_UI(retv);                                               \
    }                                                                   \
  }

LBI_IO_READ_OR_WRITE(read,       , lbt_EPOLLIN );
LBI_IO_READ_OR_WRITE(write, const, lbt_EPOLLOUT);

/*
  returns after reading/writing the whole requested amount of data. if
  an error is encountered, the thread is destructed.
*/
#define LBI_IO_READ_OR_WRITE_FULLY(read_or_write, bufdecl)              \
  static void lb_io_##read_or_write##_fully(lb_thread_t* th, uintptr_t fd, void bufdecl* buf, uintptr_t len) \
  {                                                                     \
    while (len > 0) {                                                   \
      uintptr_t amt = lb_io_##read_or_write(th, fd, buf, len);          \
      buf += amt;                                                       \
      len -= amt;                                                       \
    }                                                                   \
  }

LBI_IO_READ_OR_WRITE_FULLY(read ,      );
LBI_IO_READ_OR_WRITE_FULLY(write, const);

/*
  returns the client file descriptor after accepting a connection. if
  an error is encountered, the thread is destructed.
*/
static uintptr_t lb_io_accept(lb_thread_t* th, uintptr_t fd_server)
{
  while (1) {
    intptr_t retv = lbt_accept_simple(fd_server);
    
    if (retv < 0) {
      if (LBI_IO_TRYAGAIN) {
        //lb_breakpoint(1);
        lb_switch_epoll_wait(th, fd_server, lbt_EPOLLIN);
        //lb_breakpoint(2);
        continue;
      } else {
        //lb_breakpoint(3);
        lb_switch_destruct_thread(th, th);
      }
    }
    
    return LB_UI(retv);
  }
}

/*
  the following are helper functions that read and write
  byte(8)/short(16)/long(32)/quad(64) values in network byte order.
*/

static uint8_t lb_io_nbo_read_b(lb_thread_t* th, uintptr_t fd)
{
  uint8_t v;
  lb_io_read_fully(th, fd, &v, sizeof(v));
  return v;
}

static uint16_t lb_io_nbo_read_s(lb_thread_t* th, uintptr_t fd)
{
  uint16_t v;
  lb_io_read_fully(th, fd, &v, sizeof(v));
  v = lb_bswap_16(v);
  return v;
}

static uint32_t lb_io_nbo_read_l(lb_thread_t* th, uintptr_t fd)
{
  uint32_t v;
  lb_io_read_fully(th, fd, &v, sizeof(v));
  v = lb_bswap_32(v);
  return v;
}

static uint64_t lb_io_nbo_read_q(lb_thread_t* th, uintptr_t fd)
{
  uint64_t v;
  lb_io_read_fully(th, fd, &v, sizeof(v));
  v = lb_bswap_64(v);
  return v;
}

static void lb_io_nbo_write_b(lb_thread_t* th, uintptr_t fd, uint8_t v)
{
  lb_io_write_fully(th, fd, &v, sizeof(v));
}

static void lb_io_nbo_write_s(lb_thread_t* th, uintptr_t fd, uint16_t v)
{
  v = lb_bswap_16(v);
  lb_io_write_fully(th, fd, &v, sizeof(v));
}

static void lb_io_nbo_write_l(lb_thread_t* th, uintptr_t fd, uint32_t v)
{
  v = lb_bswap_32(v);
  lb_io_write_fully(th, fd, &v, sizeof(v));
}

static void lb_io_nbo_write_q(lb_thread_t* th, uintptr_t fd, uint64_t v)
{
  v = lb_bswap_64(v);
  lb_io_write_fully(th, fd, &v, sizeof(v));
}
