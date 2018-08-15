/*
  nbd-hyperbolic - a caching nbd proxy
  copyright (c) 2017 by andrei borac
*/

#include "./libaboon-builder.h"

#define TR LB_TR
#define PV LB_PV
#define AV LB_AV
#define DG LB_DG

static bool my_read_fixed(lb_thread_t* th, uintptr_t fd, char const* fixed)
{
  char buf[lb_strlen(fixed)];
  lb_io_read_fully(th, fd, buf, sizeof(buf));
  return lb_memcmp(buf, fixed, sizeof(buf));
}

static void my_write_fixed(lb_thread_t* th, uintptr_t fd, char const* str)
{
  lb_io_write_fully(th, fd, str, lb_strlen(str));
}

#define LSA LB_SWITCH_ASSURE
#define LSA_LBT_OK LB_SWITCH_ASSURE_LBT_OK

enum {
  NH_FRONTEND_ANY_LISTEN_BACKLOG = 16,
  NH_FRONTEND_NBD_TIMEOUT_NEGOTIATION_MS = 1000,
  NH_BACKEND_HTTP_TIMEOUT_CONNECT_MS = 10000,
  NH_BACKEND_HTTP_TIMEOUT_ROUNDTRIP_MS = 10000,
  NH_IMPROVER_BUFIO_BUFSIZ = 65536,
  NH_IMPROVER_AIO_PARALLELISM = 128,
  NH_IMPROVER_HEARTBEAT_INTERVAL_MS = 1000,
  NH_IMPROVER_TB_CONNECT_TRICKLE_EVERY = 1,
};

enum {
  NH_BUFFER_STATE_READ      = 0,
  NH_BUFFER_STATE_FETCH     = 1,
  NH_BUFFER_STATE_WRITEBACK = 2,
  NH_BUFFER_STATE_HOLD      = 3,
};

static bool nh_buffer_state_is_complete(uintptr_t state)
{
  return ((state == NH_BUFFER_STATE_WRITEBACK) || (state == NH_BUFFER_STATE_HOLD));
}

LB_TYPEBOTH(nh_buffer_t)
{
  uint8_t*  buf; /* buffer data */
  uintptr_t len; /* buffer length */
  
  /*
    fields below this point should only be accessed by the improver.
  */
  
  uintptr_t reference_count;
  
  uintptr_t state;
  uintptr_t state_fetch_count;
  
  uint64_t absolute_offset;
};

/*
  
  MODULE:frontend_any
  
*/

LB_TYPEBOTH(nh_frontend_any_a_t)
{
  uintptr_t fd_client;
};

static void module_frontend_any_a(lb_thread_t* th, lb_alloc_t* ac, uintptr_t fd_server, lb_queue_t* qu_out)
{
  lb_io_set_nonblocking(fd_server);
  
  LSA_LBT_OK(lbt_listen(fd_server, NH_FRONTEND_ANY_LISTEN_BACKLOG));
  
  while (true) {
    AV(0, "enter accept");
    uintptr_t fd_client = lb_io_accept(th, fd_server);
    AV(fd_client, "leave accept");
    LB_ALLOC_DECL(nh_frontend_any_a_t, req, ac);
    
    req->fd_client = fd_client;
    
    lb_queue_push(qu_out, req);
  }
}

/*
  
  MODULE:frontend_nbd_r
  
*/

LB_TYPEBOTH(nh_frontend_nbd_r_t)
{
  uintptr_t conn_id;
  
  uint64_t  handle;
  uint64_t  offset;
  uintptr_t length;
};

static void module_frontend_nbd_r(lb_thread_t* th, lb_watchdog_t* wd, lb_alloc_t* ac, uint64_t sz, uintptr_t fd, uintptr_t conn_id, lb_queue_t* qu_out)
{
  uintptr_t const NBD_FLAG_FIXED_NEWSTYLE = 0x1;
  uintptr_t const NBD_FLAG_NO_ZEROES      = 0x2;
  
  uintptr_t const NBD_FLAG_C_FIXED_NEWSTYLE = 0x1;
  uintptr_t const NBD_FLAG_C_NO_ZEROES      = 0x2;
  
  uintptr_t const NBD_OPT_EXPORT_NAME = 0x1;
  
  uintptr_t const NBD_FLAG_HAS_FLAGS = 0x1;
  uintptr_t const NBD_FLAG_READ_ONLY = 0x2;
  
  /*
    negotiation is under a watchdog timeout, so that we hang up
    quickly on a protocol mismatch.
  */
  {
    lb_watchdog_interval(wd, NH_FRONTEND_NBD_TIMEOUT_NEGOTIATION_MS);
    lb_watchdog_tickle(wd);
    
    // NBD negotiation
    {
      my_write_fixed(th, fd, "NBDMAGIC");
      my_write_fixed(th, fd, "IHAVEOPT");
      lb_io_nbo_write_s(th, fd, ((uint16_t)(NBD_FLAG_FIXED_NEWSTYLE | NBD_FLAG_NO_ZEROES)));
      
      uint32_t client_flags = lb_io_nbo_read_l(th, fd);
      PV(client_flags);
      LSA((client_flags == (NBD_FLAG_C_FIXED_NEWSTYLE | NBD_FLAG_C_NO_ZEROES)));
      LSA(my_read_fixed(th, fd, "IHAVEOPT"));
      LSA((lb_io_nbo_read_l(th, fd) == (NBD_OPT_EXPORT_NAME)));
      LSA((lb_io_nbo_read_l(th, fd) == 0));
      lb_io_nbo_write_q(th, fd, sz);
      lb_io_nbo_write_s(th, fd, ((uint16_t)(NBD_FLAG_HAS_FLAGS | NBD_FLAG_READ_ONLY)));
    }
    
    lb_watchdog_disable(wd);
  }
  
  /*
    no watchdog from here on, as the client is in no way obligated to
    make requests (and nbd clients might be fragile to
    disconnections).
  */
  
  while (true) {
    struct {
      uint32_t magic;
      
      uint16_t flags;
      uint16_t rtype;
      
      uint64_t handle;
      uint64_t offset;
      uint32_t length;
    } LB_PACKED header;
    
    lb_io_read_fully(th, fd, (&(header)), sizeof(header));
    
    LSA((header.magic == 0x13956025));
    
    LB_BSWAP_16(header.flags);
    LB_BSWAP_16(header.rtype);
    LB_BSWAP_64(header.handle);
    LB_BSWAP_64(header.offset);
    LB_BSWAP_32(header.length);
    
    /*
      check satisfiability of the request.
    */
    LB_PV(header.magic);
    LB_PV(header.flags);
    LB_PV(header.rtype);
    LB_PV(header.handle);
    LB_PV(header.offset);
    LB_PV(header.length);
    LB_PV(sz);
    LSA(((header.offset + header.length) <= sz));
    
    LB_ALLOC_DECL(nh_frontend_nbd_r_t, req, ac);
    
    req->conn_id = conn_id;
    
    req->handle = header.handle;
    req->offset = header.offset;
    req->length = header.length;
    
    lb_queue_push(qu_out, req);
  }
}

/*
  
  MODULE:frontend_nbd_w
  
*/

LB_TYPEBOTH(nh_frontend_nbd_w_t)
{
  uintptr_t conn_id;
  
  uint64_t handle;
  
  uintptr_t offset; /* into first buffer */
  uintptr_t length; /* total length */
  
  lb_queue_t* buffers; /* -> nh_buffer_t */
};

static void module_frontend_nbd_w(lb_thread_t* th, uintptr_t fd, lb_work_queue_t* wq_inp, lb_queue_t* qu_out)
{
  /*
    no watchdog for any of this. we allow the nbd client to postpone
    reading from the socket for arbitrary durations.
  */
  
  while (true) {
    nh_frontend_nbd_w_t* req = ((nh_frontend_nbd_w_t*)(lb_work_queue_obtain(th, wq_inp)));
    lb_work_queue_push_cleanup_resubmit(th, wq_inp, req);
    
    struct {
      uint32_t magic;
      
      uint32_t flags;
      
      uint64_t handle;
    } LB_PACKED header;
    
    header.magic = 0x98664467;
    
    header.flags = 0;
    
    header.handle = req->handle;
    
    LB_BSWAP_64(header.handle);
    
    lb_io_write_fully(th, fd, (&(header)), sizeof(header));
    
    /*
      now write the data.
    */
    {
      uintptr_t offset = req->offset;
      uintptr_t length = req->length;
      
      lb_queue_peek_all_tm(nh_buffer_t, arr, len, req->buffers);
      
      for (uintptr_t i = 0; i < len; i++) {
        LB_ASSURE(offset < arr[i]->len);
        LB_ASSURE(length > 0);
        uintptr_t amt = LB_MIN(length, (arr[i]->len - offset));
        lb_io_write_fully(th, fd, (arr[i]->buf + offset), amt);
        offset = 0;
        length -= amt;
      }
    }
    
    /*
      request is now processed.
    */
    lb_switch_pull_cleanup(th); /* req */
    lb_queue_push(qu_out, req);
  }
}

/*
  
  MODULE:backend_http_wr
  
*/

static void module_backend_http_wr(lb_thread_t* th, lb_watchdog_t* wd, lb_alloc_t* ac, uint32_t host, uint16_t port, char const* hostname, char const* url, lb_token_bucket_t* tb_conn, bool tb_conn_refund, lb_work_queue_t* wq_inp, lb_queue_t* qu_out)
{
  /*
    create buffer.
  */
  const uintptr_t buf_siz = 8192;
  char* buf = ((char*)(lb_alloc(ac, buf_siz)));
  lb_switch_push_cleanup_free(th, ac, buf, buf_siz);
  
  /*
    create socket. don't connect yet, just create the socket we will
    eventually connect.
  */
  uintptr_t fd = LSA_LBT_OK(lbt_socket(lbt_AF_INET, lbt_SOCK_STREAM, 0));
  lb_io_push_cleanup_close_fd(th, fd);
  lb_io_set_nonblocking(fd);
  
  /*
    dequeue one element before connecting. this makes sure we don't
    blindly attempt to reconnect after a connection dropped in the
    case that there is nothing to do anyways - the reconnection should
    be deferred until there are pending tasks.
  */
  nh_buffer_t* buffer = ((nh_buffer_t*)(lb_work_queue_obtain(th, wq_inp)));
  lb_work_queue_push_cleanup_resubmit(th, wq_inp, buffer);
  
  /*
    connect!
  */
  {
    AV(0, "taking token");
    lb_token_bucket_obtain(th, tb_conn, 1);
    AV(0, "got token");
    
    lb_watchdog_interval(wd, NH_BACKEND_HTTP_TIMEOUT_CONNECT_MS);
    
    {
      lbt_sockaddr_in_t addr;
      LB_BZERO(addr);
      addr.family = lbt_AF_INET;
      addr.host = host;
      addr.port = port;
      
      AV(0, "connecting");
      intptr_t retv = lbt_connect(fd, (&(addr)), sizeof(addr));
      AV(retv, "retv_connect");
      
      LSA(((retv == 0) || (retv == -lbt_EINPROGRESS)));
      
      if (retv == -lbt_EINPROGRESS) {
        AV(0, "enter io_write_wait_ready");
        lb_io_write_wait_ready(th, fd);
        AV(0, "leave io_write_wait_ready");
      }
    }
    
    AV(0, "connected");
    
    lb_watchdog_disable(wd);
  }
  
  lb_watchdog_interval(wd, NH_BACKEND_HTTP_TIMEOUT_ROUNDTRIP_MS);
  
  bool first_request = true;
  
  while (true) {
    /*
      here the watchdog covers the entire HTTP transaction from
      beginning to end.
    */
    lb_watchdog_tickle(wd);
    
    {
      /* send request */
      {
        LB_ASSURE_GTZ(buffer->len);
        
        uint64_t range_A = buffer->absolute_offset;
        uint64_t range_B = (buffer->absolute_offset + buffer->len - 1);
        
#define X "sssss8us8us"
#define Y "GET ", url, " HTTP/1.1\r\nHost: ", hostname, "\r\nRange: bytes=", (&(range_A)), "-", (&(range_B)), "\r\nConnection: keep-alive\r\n\r\n"
        
        /*
          lb_print_s will add an uncounted null terminator, so the
          returned size must be -strictly- less than the buffer
          capacity.
        */
        uintptr_t len;
        LB_ASSURE(((len = lb_print_s(NULL, X, Y)) < buf_siz));
        LB_ASSURE((lb_print_s(buf, X, Y) == len));
        
#undef X
#undef Y
        
        lb_io_write_fully(th, fd, buf, len);
      }
      
      /* receive response */
      {
        uintptr_t len = 0;
        
        uint8_t const* end = NULL;
        
        while ((!(end = ((uint8_t*)(lb_memmem(buf, len, "\r\n\r\n", 4)))))) {
          LSA(len < buf_siz);
          uintptr_t amt = lb_io_read(th, fd, (buf + len), (buf_siz - len));
          PV(amt);
          len += amt;
        }
        
        PV(end);
        PV(end[0]);
        PV(end[1]);
        PV(end[2]);
        PV(end[3]);
        
        end += 4;
        
        uint8_t*  dst_buf = buffer->buf;
        uintptr_t dst_len = buffer->len;
        
        {
          uintptr_t rem = LB_PTRDIF((buf + len), end);
          
          LSA(rem <= dst_len);
          lb_memcpy(dst_buf, end, rem);
          dst_buf += rem;
          dst_len -= rem;
        }
        
        lb_io_read_fully(th, fd, dst_buf, dst_len);
      }
    }
    
    /*
      end of HTTP transaction; disable the watchdog.
    */
    lb_watchdog_disable(wd);
    
    /*
      request is now processed.
    */
    lb_switch_pull_cleanup(th); /* buffer */
    AV(buffer, "http complete");
    lb_queue_push(qu_out, buffer);
    
    /*
      handle token refund.
    */
    if (first_request && tb_conn_refund) {
      lb_token_bucket_submit(th, tb_conn, 1);
      first_request = false;
    }
    
    /*
      get another request.
    */
    buffer = ((nh_buffer_t*)(lb_work_queue_obtain(th, wq_inp)));
    lb_work_queue_push_cleanup_resubmit(th, wq_inp, buffer);
  }
}

LB_TYPEBOTH(nh_check_t)
{
  lb_sha256_state_t sha256;
};

LB_TYPEBOTH(nh_nbd_pair_t)
{
  uintptr_t conn_id;
  
  bool zombie;
  
  uintptr_t fd_nbd_r;
  uintptr_t fd_nbd_w;
  
  lb_work_queue_t* wq_nbd_w_inp;
  
  lb_thread_t* th_nbd_r;
  lb_thread_t* th_nbd_w;
};

LB_TYPEBOTH(g_t)
{
  char const* const* envp;
  
  lb_alloc_t* ac;
  lb_switch_t* sw;
  
  uint64_t image_size;

  struct {
    bool use;
    
    union {
      struct {
        uint32_t user_a;
        uint32_t user_b;
        uint32_t user_c;
        uint32_t user_d;
        uint32_t block_index;
      } as_tag;
      
      lb_sha256_block_t as_block;
    } block_header;
    
    uintptr_t block_size_log;
    uintptr_t block_size;
    uintptr_t block_count;
    
    nh_check_t* block_check;
    
    uintptr_t fd;
    uint64_t  fd_offset;
  } cache;
  
  lb_queue_t* qu_any_a;
  
  uintptr_t nbd_conn_id_next;
  lb_stack_t* sk_nbds; /* -> nh_nbd_pair_t */
  lb_queue_t* qu_nbd_r_out;
  lb_queue_t* qu_nbd_w_out;
  
  lb_token_bucket_t* tb_connect;
  
  lb_work_queue_t* wq_http_wr;
  lb_queue_t*      qu_http_wr;
  
  lb_queue_t* qu_ah_out;
  lb_aio_hub_t* ah;
  
  lb_queue_t* qu_heartbeat;
  
  lb_stack_t* buffers; /* -> nh_buffer_t */
  lb_stack_t* pending; /* -> nh_frontend_nbd_w_t */
};

g_t g;

#define AC g.ac

static char const* getenv(char const* key)
{
  return lb_misc_getenv(g.envp, key);
}

static char const* getenv_s(char const* key)
{
  char const* envvar = lb_misc_getenv(g.envp, key);
  
  LB_ASSURE(envvar);
  
  return envvar;
}

static bool getenv_b(char const* key)
{
  char const* envvar = lb_misc_getenv(g.envp, key);
  
  LB_ASSURE(envvar);
  
  char x = *envvar;
  
  return ((x == '1') || (x == 'y') || (x == 'Y'));
}

static uint64_t getenv_u_64(char const* key)
{
  char const* envvar = getenv_s(key);
  
  return lb_atou_64(envvar);
}

static uint32_t getenv_u_32(char const* key)
{
  uint64_t value = getenv_u_64(key);
  LB_ASSURE((value < (((uint64_t)(1)) << 32)));
  return ((uint32_t)(value));
}

static uint16_t getenv_u_16(char const* key)
{
  uint64_t value = getenv_u_64(key);
  LB_ASSURE((value < (((uint64_t)(1)) << 16)));
  return ((uint16_t)(value));
}

static uint32_t getenv_u_32_n(char const* key)
{
  uint32_t value = getenv_u_32(key);
  PV(value);
  value = lb_bswap_32(value);
  PV(lb_bswap_32(value));
  return value;
}

static uint16_t getenv_u_16_n(char const* key)
{
  uint16_t value = getenv_u_16(key);
  PV(value);
  value = lb_bswap_16(value);
  PV(lb_bswap_16(value));
  return value;
}

LB_SWITCH_PUSH_CLEANUP_VARIANT_0(_void);

static void start_frontend_continue_thread_proc(lb_thread_t* th, void* parm_fd_server)
{
  uintptr_t fd_server = LB_U(parm_fd_server);
  
  lb_io_push_cleanup_close_fd(th, fd_server);
  
  module_frontend_any_a(th, g.ac, fd_server, g.qu_any_a);
}

static void start_frontend_continue(uintptr_t fd_server)
{
  lb_switch_create_thread(g.sw, start_frontend_continue_thread_proc, ((void*)(fd_server)));
}

static void start_frontend_unix(void)
{
  uintptr_t fd_server = LBT_OK(lbt_socket(lbt_AF_UNIX, lbt_SOCK_STREAM, 0));
  
  {
    lbt_sockaddr_un_t addr;
    LB_BZERO(addr);
    addr.family = lbt_AF_UNIX;
    char const* addr_path = getenv_s("NH_FRONTEND_UNIX_SOCKET");
    lb_memcpy(addr.path, addr_path, (lb_strlen(addr_path) + 1));
    lbt_unlink(addr_path); /* ignore error as it may not exist */
    LBT_OK(lbt_bind(fd_server, (&(addr)), sizeof(addr)));
    LBT_OK(lbt_chmod(addr_path, 0700));
  }
  
  start_frontend_continue(fd_server);
}

static void start_frontend_tcp(void)
{
  uintptr_t fd_server = LBT_OK(lbt_socket(lbt_AF_INET, lbt_SOCK_STREAM, 0));
  
  uintptr_t const const_1 = 1;
  LBT_OK(lbt_setsockopt(fd_server, lbt_SOL_SOCKET, lbt_SO_REUSEADDR, (&(const_1)), sizeof(int)));
  
  {
    lbt_sockaddr_in_t addr;
    LB_BZERO(addr);
    addr.family = lbt_AF_INET;
    addr.host = getenv_u_32_n("NH_FRONTEND_TCP_HOST");
    addr.port = getenv_u_16_n("NH_FRONTEND_TCP_PORT");
    PV(addr.host);
    PV(addr.port);
    LBT_OK(lbt_bind(fd_server, (&(addr)), sizeof(addr)));
  }
  
  start_frontend_continue(fd_server);
}

LB_SWITCH_CREATE_THREAD_VARIANT_0(_void);

#if 0

static void start_backend_nbd_proc(lb_thread_t* th)
{
}

static void start_backend_nbd(void)
{
  /*
    connect!
  */
  
  lb_switch_create_thread__void(g.sw, start_backend_nbd_proc);
  lb_switch_create_thread_backend_nbd(g.sw, backend_nbd);
}

#endif

static void start_backend_http_proc(lb_thread_t* th)
{
  AV(0, "start_backend_http_proc");
  
  lb_switch_resurrect_me(th, start_backend_http_proc);
  
  lb_watchdog_t* wd = lb_watchdog_irreversible(th, AC);
  
  uint32_t host = getenv_u_32_n("NH_BACKEND_HTTP_HOST");
  uint16_t port = getenv_u_16_n("NH_BACKEND_HTTP_PORT");
  
  char const* hostname = getenv_s("NH_BACKEND_HTTP_HOSTNAME");
  char const* url      = getenv_s("NH_BACKEND_HTTP_URL");
  
  bool tb_conn_refund = getenv_b("NH_BACKEND_HTTP_TOKEN_REFUND");
  
  module_backend_http_wr(th, wd, AC, host, port, hostname, url, g.tb_connect, tb_conn_refund, g.wq_http_wr, g.qu_http_wr);
  
  LB_ILLEGAL;
}

static void start_backend_http(void)
{
  uintptr_t parallelism = lb_misc_narrow_64_ptr(LB_ASSURE_GTZ(getenv_u_64("NH_BACKEND_HTTP_PARALLELISM")));
  
  {
    uintptr_t bucket_capacity = parallelism; /* (getenv_b("NH_BACKEND_HTTP_CONN_SPAM") ? (1UL << 32) : parallelism); */
    
    g.tb_connect = lb_token_bucket_create(AC, bucket_capacity, NH_IMPROVER_TB_CONNECT_TRICKLE_EVERY);
    lb_token_bucket_submit_by_switch(g.sw, g.tb_connect, bucket_capacity);
  }
  
  g.wq_http_wr = lb_work_queue_create(AC);
  g.qu_http_wr = lb_queue_create(AC);
  
  for (uintptr_t i = 0; i < parallelism; i++) {
    lb_switch_create_thread__void(g.sw, start_backend_http_proc);
  }
}

static void improver_initialize(void)
{
  PV((g.image_size = getenv_u_64("NH_IMAGE_SIZE")));
  
  /*
    initialize the cache first. this makes sure we are actually ready
    to process requests immediately after we create the server socket.
  */
  {
    g.cache.use = getenv_b("NH_CACHE_ENABLE");
    
    LB_BZERO(g.cache.block_header);
    
    g.cache.block_header.as_tag.user_a = getenv_u_32("NH_CACHE_USER_A");
    g.cache.block_header.as_tag.user_b = getenv_u_32("NH_CACHE_USER_B");
    g.cache.block_header.as_tag.user_c = getenv_u_32("NH_CACHE_USER_C");
    g.cache.block_header.as_tag.user_d = getenv_u_32("NH_CACHE_USER_D");
    
    /*
      cacheless operation not supported yet.
    */
    LB_ASSURE(g.cache.use);
    
    g.cache.block_size_log = lb_misc_narrow_64_ptr(getenv_u_64("NH_CACHE_BLOCK_SIZE_LOG"));
    LB_ASSURE(g.cache.block_size_log >= 9);
    LB_ASSURE(g.cache.block_size_log <= 30);
    
    g.cache.block_size = (1UL << g.cache.block_size_log);
    
    {
      uint64_t q;
      lb_div_64_by_32((g.image_size + (g.cache.block_size - 1)), lb_misc_narrow_ptr_32(g.cache.block_size), (&q));
      g.cache.block_count = lb_misc_narrow_64_ptr(q);
    }
    
    g.cache.block_check = ((nh_check_t*)(lb_alloc(AC, (g.cache.block_count * sizeof(nh_check_t)))));
    
    /*
      read the checksums.
    */
    {
      uintptr_t fd = LBT_OK(lbt_open(getenv_s("NH_CACHE_CHECKSUM_FILE"), (lbt_O_RDONLY), 0000));
      
      lb_bufio_t* bu = lb_bufio_create(AC, NH_IMPROVER_BUFIO_BUFSIZ);
      
      for (uintptr_t i = 0; i < g.cache.block_count; i++) {
        LB_ASSURE(lb_bufio_read(bu, fd, (&(g.cache.block_check[i])), (sizeof(g.cache.block_check[i]))));
      }
      
      lb_bufio_delete(bu, AC);
      
      LBT_OK(lbt_close(fd));
    }
    
    /*
      open the cache file.
    */
    g.cache.fd = LBT_OK(lbt_open(getenv_s("NH_CACHE_BACKING_FILE"), (lbt_O_RDWR), 0000));
    g.cache.fd_offset = lb_misc_narrow_64_ptr(getenv_u_64("NH_CACHE_BACKING_OFFSET"));
  }
  
  g.qu_any_a = lb_queue_create(AC);
  
  g.nbd_conn_id_next = 1;
  g.sk_nbds = lb_stack_create(AC);
  g.qu_nbd_r_out = lb_queue_create(AC);
  g.qu_nbd_w_out = lb_queue_create(AC);
  
  if (getenv_b("NH_FRONTEND_UNIX_ENABLE")) {
    start_frontend_unix();
  }
  
  if (getenv_b("NH_FRONTEND_TCP_ENABLE")) {
    start_frontend_tcp();
  }
  
  start_backend_http();
  
  g.qu_ah_out = lb_queue_create(AC);
  g.ah = lb_aio_hub_create(g.sw, AC, NH_IMPROVER_AIO_PARALLELISM, g.qu_ah_out);
  
  g.qu_heartbeat = lb_queue_create(AC);
  lb_heartbeat_launch(g.sw, AC, NH_IMPROVER_HEARTBEAT_INTERVAL_MS, g.qu_heartbeat, NULL, NULL, NULL);
  
  g.buffers = lb_stack_create(AC);
  g.pending = lb_stack_create(AC);
}

static void improver_accept_nbd_rw_cleanup_proc(lb_thread_t* th, nh_nbd_pair_t* pair)
{
  if (!(pair->zombie)) {
    /*
      set zombie so we only enter here once.
    */
    pair->zombie = true;
    
    /*
      destruct the other thread too.
    */
    if (pair->th_nbd_r != th) lb_switch_destruct_thread(th, pair->th_nbd_r);
    if (pair->th_nbd_w != th) lb_switch_destruct_thread(th, pair->th_nbd_w);
    
    /*
      close the descriptors.
    */
    lbt_close(pair->fd_nbd_r);
    lbt_close(pair->fd_nbd_w);
    
    /*
      fast-forward pending writes to completion.
    */
    while (lb_work_queue_sense(pair->wq_nbd_w_inp)) {
      lb_queue_push(g.qu_nbd_w_out, lb_work_queue_obtain_nonblocking(pair->wq_nbd_w_inp));
    }
    
    /*
      unlink and deallocate the pair structure.
    */
    {
      lb_stack_delete_all(g.sk_nbds, pair);
      LB_ALLOC_FREE(pair->wq_nbd_w_inp, AC);
      LB_ALLOC_FREE(pair, AC);
    }
  }
}

static void improver_accept_nbd_r_thread_proc(lb_thread_t* th, nh_nbd_pair_t* pair)
{
  lb_switch_push_cleanup_tm_1(th, improver_accept_nbd_rw_cleanup_proc, pair);
  lb_watchdog_t* wd = lb_watchdog_irreversible(th, AC);
  module_frontend_nbd_r(th, wd, AC, g.image_size, pair->fd_nbd_r, pair->conn_id, g.qu_nbd_r_out);
}

static void improver_accept_nbd_w_thread_proc(lb_thread_t* th, nh_nbd_pair_t* pair)
{
  lb_switch_push_cleanup_tm_1(th, improver_accept_nbd_rw_cleanup_proc, pair);
  module_frontend_nbd_w(th, pair->fd_nbd_w, pair->wq_nbd_w_inp, g.qu_nbd_w_out);
}

static void improver_handle_accept(void)
{
  while (lb_queue_sense(g.qu_any_a)) {
    uintptr_t fd_client;
    
    {
      nh_frontend_any_a_t* conn = ((nh_frontend_any_a_t*)(lb_queue_pull(g.qu_any_a)));
      fd_client = conn->fd_client;
      LB_ALLOC_FREE(conn, AC);
    }
    AV(fd_client, "fd_client in handle_accept");
    LB_ALLOC_DECL(nh_nbd_pair_t, pair, AC);
    
    pair->conn_id = ((g.nbd_conn_id_next)++);
    lb_stack_push(g.sk_nbds, pair);
    
    pair->zombie = false;
    
    pair->fd_nbd_r = fd_client;
    pair->fd_nbd_w = LBT_OK(lbt_dup(fd_client));
    
    lb_io_set_nonblocking(pair->fd_nbd_r);
    lb_io_set_nonblocking(pair->fd_nbd_w);
    
    pair->wq_nbd_w_inp = lb_work_queue_create(AC);
    
    pair->th_nbd_r = lb_switch_create_thread_tm_1(g.sw, improver_accept_nbd_r_thread_proc, pair);
    pair->th_nbd_w = lb_switch_create_thread_tm_1(g.sw, improver_accept_nbd_w_thread_proc, pair);
  }
}

static nh_nbd_pair_t* improver_get_pair_for_id(uintptr_t conn_id)
{
  nh_nbd_pair_t* found = NULL;
  
  lb_stack_peek_all_tm(nh_nbd_pair_t, arr, len, g.sk_nbds);
  
  for (uintptr_t i = 0; i < len; i++) {
    if (arr[i]->conn_id == conn_id) {
      found = arr[i];
      break;
    }
  }
  
  return found;
}

static nh_buffer_t* improver_get_buffer_at(uint64_t absolute_offset)
{
  /*
    find existing.
  */
  {
    lb_stack_peek_all_tm(nh_buffer_t, arr, len, g.buffers);
    
    for (uintptr_t i = 0; i < len; i++) {
      if (arr[i]->absolute_offset == absolute_offset) {
        arr[i]->reference_count++;
        return arr[i];
      }
    }
  }
  
  /*
    create new.
  */
  {
    LB_ALLOC_DECL(nh_buffer_t, buffer, AC);
    
    buffer->buf = ((uint8_t*)(lb_alloc(AC, (buffer->len = g.cache.block_size))));
    
    /*
      reference count gets two: one for the caller, and one for the
      background read/fetch/writeback process.
    */
    buffer->reference_count = 2;
    
    buffer->state = NH_BUFFER_STATE_READ;
    buffer->state_fetch_count = 0;
    
    buffer->absolute_offset = absolute_offset;
    
    AV(buffer->absolute_offset, "submitting read");
    PV(buffer->buf);
    lb_aio_hub_submit_read(g.ah, g.cache.fd, buffer->buf, buffer->len, (g.cache.fd_offset + buffer->absolute_offset), buffer);
    
    lb_stack_push(g.buffers, buffer);
    
    return buffer;
  }
}

static void improver_release_buffer(nh_buffer_t* buffer)
{
  AV(buffer->reference_count, "pre-decrement reference count");
  
  if ((--(buffer->reference_count)) == 0) {
    lb_stack_delete_all(g.buffers, buffer);
    lb_alloc_free(AC, buffer->buf, g.cache.block_size);
    LB_ALLOC_FREE(buffer, AC);
  }
}

static void improver_handle_nbd_incoming(void)
{
  while (lb_queue_sense(g.qu_nbd_r_out)) {
    nh_frontend_nbd_r_t* prereq = ((nh_frontend_nbd_r_t*)(lb_queue_pull(g.qu_nbd_r_out)));
    
    AV(prereq->conn_id, "got request");
    PV(prereq->handle);
    PV(prereq->offset);
    PV(prereq->length);
    
    nh_nbd_pair_t* pair;
    
    /*
      look up the connection id and skip if the connection no longer
      exists.
    */
    if (!(pair = improver_get_pair_for_id(prereq->conn_id))) {
      LB_ALLOC_FREE(prereq, AC);
      continue;
    }
    
    /*
      chunk up the request.
    */
    {
      LB_ALLOC_DECL(nh_frontend_nbd_w_t, req, AC);
      
      req->conn_id = prereq->conn_id;
      
      req->handle = prereq->handle;
      
      req->offset = (((uintptr_t)(prereq->offset)) & (g.cache.block_size - 1));
      req->length = prereq->length;
      
      req->buffers = lb_queue_create(AC);
      
      uint64_t absolute_offset = (prereq->offset & (~(g.cache.block_size - 1)));
      
      while (absolute_offset < (prereq->offset + prereq->length)) {
        AV(absolute_offset, "chunking");
        
        lb_queue_push(req->buffers, improver_get_buffer_at(absolute_offset));
        
        absolute_offset += g.cache.block_size;
      }
      
      lb_stack_push(g.pending, req);
      
      LB_ALLOC_FREE(prereq, AC);
    }
  }
}

static void improver_handle_nbd_outgoing(void)
{
  while (lb_queue_sense(g.qu_nbd_w_out)) {
    nh_frontend_nbd_w_t* req = ((nh_frontend_nbd_w_t*)(lb_queue_pull(g.qu_nbd_w_out)));
    
    lb_queue_peek_all_tm(nh_buffer_t, arr, len, req->buffers);
    
    for (uintptr_t i = 0; i < len; i++) {
      AV(arr[i], "dereferencing for user processes");
      improver_release_buffer(arr[i]);
    }
    
    lb_queue_delete(req->buffers, AC);
    
    LB_ALLOC_FREE(req, AC);
  }
}

static void improver_buffer_checksum(lb_sha256_state_t* state, uint8_t* buf)
{
  lb_sha256_init(state);
  uint64_t total = 0;
  lb_sha256_calc_len(state, (&(total)), ((uint8_t const*)(&(g.cache.block_header.as_block))), sizeof(g.cache.block_header.as_block), false, 0);
  lb_sha256_calc_len(state, (&(total)), buf, g.cache.block_size, true, 0);
  lb_sha256_calc_len(state, (&(total)), NULL, 0, false, 1);
}

static bool improver_buffer_validate(nh_buffer_t* buffer)
{
  uintptr_t block_index = lb_misc_narrow_64_ptr(buffer->absolute_offset >> g.cache.block_size_log);
  
  LB_ASSURE((block_index < g.cache.block_count));
  
  g.cache.block_header.as_tag.block_index = ((uint32_t)(block_index));
  
  lb_sha256_state_t state;
  LB_ASSURE(buffer->len = g.cache.block_size);
  improver_buffer_checksum((&(state)), buffer->buf);
  
  return (lb_memcmp((&(state)), (&(g.cache.block_check[block_index].sha256)), sizeof(lb_sha256_state_t)));
}

static void improver_handle_aio_completion(void)
{
  while (lb_queue_sense(g.qu_ah_out)) {
    nh_buffer_t* buffer = ((nh_buffer_t*)(lb_queue_pull(g.qu_ah_out)));
    
    void background_process_complete(void)
    {
      buffer->state = NH_BUFFER_STATE_HOLD;
      AV(buffer, "derefencing for background process");
      improver_release_buffer(buffer);
    }
    
    switch (buffer->state) {
    case NH_BUFFER_STATE_READ:
      {
        if (improver_buffer_validate(buffer)) {
          AV(buffer->absolute_offset, "completion");
          PV(buffer->buf);
          background_process_complete();
        } else {
          AV(buffer->absolute_offset, "completion -> fetching");
          PV(buffer->buf);
          buffer->state = NH_BUFFER_STATE_FETCH;
          
          buffer->state_fetch_count++;
          lb_work_queue_submit_by_switch(g.sw, g.wq_http_wr, buffer);
        }
        
        break;
      }
      
    case NH_BUFFER_STATE_WRITEBACK:
      {
        AV(buffer->absolute_offset, "completion (of writeback)");
        PV(buffer->buf);
        background_process_complete();
        
        break;
      }

    default:
      {
        LB_ILLEGAL;
        
        break;
      }
    }
  }
}

static void improver_handle_http_completion(void)
{
  while (lb_queue_sense(g.qu_http_wr)) {
    nh_buffer_t* buffer = ((nh_buffer_t*)(lb_queue_pull(g.qu_http_wr)));
    
    LB_ASSURE((buffer->state == NH_BUFFER_STATE_FETCH));
    
    if (improver_buffer_validate(buffer)) {
      buffer->state = NH_BUFFER_STATE_WRITEBACK;
      AV(buffer->absolute_offset, "submitting write");
      PV(buffer->buf);
      lb_aio_hub_submit_write(g.ah, g.cache.fd, buffer->buf, buffer->len, (g.cache.fd_offset + buffer->absolute_offset), buffer);
    } else {
      if (buffer->state_fetch_count < 2) {
        buffer->state_fetch_count++;
        lb_work_queue_submit_by_switch(g.sw, g.wq_http_wr, buffer);
      } else {
        lb_print("s", "invalid block data received (twice for the same block). bye.\n");
        LB_ILLEGAL;
      }
    }
  }
}

static bool improver_handle_satisfiable_request(nh_frontend_nbd_w_t* req)
{
  lb_queue_peek_all_tm(nh_buffer_t, arr, len, req->buffers);
  
  for (uintptr_t i = 0; i < len; i++) {
    if (!(nh_buffer_state_is_complete(arr[i]->state))) {
      return false;
    }
  }
  
  nh_nbd_pair_t* pair;
  
  if ((pair = improver_get_pair_for_id(req->conn_id)) != NULL) {
    lb_work_queue_submit_by_switch(g.sw, pair->wq_nbd_w_inp, req);
  }
  
  return true;
}

static void improver_handle_satisfiable(void)
{
  lb_stack_peek_all_tm(nh_frontend_nbd_w_t, arr, len, g.pending);
  
  for (uintptr_t i = 0; i < len; i++) {
    if (improver_handle_satisfiable_request(arr[i])) {
      lb_stack_delete_all(g.pending, arr[i]);
    }
  }
}

static void improver_handle_heartbeat(void)
{
  if (lb_queue_sense(g.qu_heartbeat)) {
    lb_queue_pull(g.qu_heartbeat);
    
    lb_token_bucket_submit_trickle_by_switch(g.sw, g.tb_connect);
    
    LB_PV(lb_stack_size(g.buffers));
    LB_PV(lb_stack_size(g.pending));
  }
}

static bool improver(void* unused LB_UNUSED)
{
  improver_handle_accept();
  improver_handle_nbd_incoming();
  improver_handle_nbd_outgoing();
  improver_handle_aio_completion();
  improver_handle_http_completion();
  improver_handle_satisfiable();
  improver_handle_heartbeat();
  
  return false;
}

static void prepare(void)
{
  PV((g.image_size = getenv_u_64("NH_IMAGE_SIZE")));
  
  LB_BZERO(g.cache.block_header);
  
  g.cache.block_header.as_tag.user_a = getenv_u_32("NH_CACHE_USER_A");
  g.cache.block_header.as_tag.user_b = getenv_u_32("NH_CACHE_USER_B");
  g.cache.block_header.as_tag.user_c = getenv_u_32("NH_CACHE_USER_C");
  g.cache.block_header.as_tag.user_d = getenv_u_32("NH_CACHE_USER_D");
  
  g.cache.block_size_log = lb_misc_narrow_64_ptr(getenv_u_64("NH_CACHE_BLOCK_SIZE_LOG"));
  LB_ASSURE(g.cache.block_size_log >= 9);
  LB_ASSURE(g.cache.block_size_log <= 30);
  
  g.cache.block_size = (1UL << g.cache.block_size_log);
  
  {
    uint64_t q;
    lb_div_64_by_32((g.image_size + (g.cache.block_size - 1)), lb_misc_narrow_ptr_32(g.cache.block_size), (&q));
    g.cache.block_count = lb_misc_narrow_64_ptr(q);
  }
  
  g.cache.fd = LBT_OK(lbt_open(getenv_s("NH_CACHE_BACKING_FILE"), (lbt_O_RDWR), 0000));
  g.cache.fd_offset = getenv_u_64("NH_CACHE_BACKING_OFFSET");
  
  for (uintptr_t i = 0; i < g.cache.block_count; i++) {
    g.cache.block_header.as_tag.block_index = ((uint32_t)(i));
    uint8_t buf[g.cache.block_size];
    LB_ASSURE((LB_UI(lbt_read(g.cache.fd, buf, sizeof(buf))) == sizeof(buf)));
    lb_sha256_state_t state;
    improver_buffer_checksum((&(state)), buf);
    LB_ASSURE((LB_UI(lbt_write(1, (&(state)), sizeof(state))) == sizeof(state)));
  }
}

LB_MAIN_SPEC
{
  LB_BZERO(g);
  
  g.envp = envp;
  
  lbt_block_signal_simple_SIGPIPE();
  
  lb_sbrk_t sb_;
  lb_sbrk_t* sb = (&(sb_));
  lb_sbrk_initialize(sb);
  
  lb_alloc_t ac_;
  g.ac = (&(ac_));
  lb_alloc_initialize(g.ac, sb);
  
  if (getenv_b("NH_PREPARE_ONLY")) {
    prepare();
    lbt_exit_simple(0);
  }
  
  lb_switch_t sw_;
  g.sw = (&(sw_));
  lb_switch_initialize(g.sw, g.ac);
  
  improver_initialize();
  
  lb_switch_event_loop(g.sw, improver, NULL);
  
  LB_ABORT;
}
