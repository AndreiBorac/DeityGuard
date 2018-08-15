/*
  instigator - a secure loader from within the OS
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
  SG_LOAD_CONFIG_MAXIMUM_LENGTH = 512,
  SG_MAC_ADDR_LEN = 6,
  SG_DHCP4_MAGIC_EL = 0x63538263,
  SG_DHCP4_ID = 0x696e7374,
  SG_DHCP4_RESPONSE_SIZE = 4096,
  SG_DNS_SERVER_IP = 0x08080808, /* public dns 8.8.8.8 */
  SG_DNS_REQUEST_SIZE = 4096,
  SG_DNS_RESPONSE_SIZE = 4096,
  SG_HTTP_RESPONSE_SIZE = 4096,
};

LB_TYPEBOTH(g_t)
{
  char const* const* argv;
  char const* const* envp;
  
  lb_alloc_t*  ac;
  lb_switch_t* sw;
  
  struct {
    bool   skip;
    void (*proc_request)(lb_thread_t*, void*, void*, void*, void*);
    void*  user_request_a;
    void*  user_request_b;
    void*  user_request_c;
    void*  user_request_d;
  } hb;
};

g_t g;

#define AC (g.ac)

static void hb_activate(lb_thread_t* th, bool tg, void (*proc_request)(lb_thread_t*, void*, void*, void*, void*), void* user_request_a, void* user_request_b, void* user_request_c, void* user_request_d)
{
  g.hb.skip = false;
  g.hb.proc_request   = proc_request;
  g.hb.user_request_a = user_request_a;
  g.hb.user_request_b = user_request_b;
  g.hb.user_request_c = user_request_c;
  g.hb.user_request_d = user_request_d;
  
  if (tg) {
    g.hb.skip = true;
    proc_request(th, user_request_a, user_request_b, user_request_c, user_request_d);
  }
}

#define hb_activate_tm_2(th, tg, proc, user1, user2)                    \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user1), __typeof__(user2)) = (proc); \
    __typeof__(user1) __tm_user1 = (user1);                             \
    __typeof__(user2) __tm_user2 = (user2);                             \
    void*             __tm_user3 = NULL;                                \
    void*             __tm_user4 = NULL;                                \
    hb_activate(th, tg, ((void (*)(lb_thread_t*, void*, void*, void*, void*))(__tm_proc)), ((void*)(__tm_user1)), ((void*)(__tm_user2)), ((void*)(__tm_user3)), ((void*)(__tm_user4))); \
  })

#define hb_activate_tm_3(th, tg, proc, user1, user2, user3)             \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user1), __typeof__(user2), __typeof__(user3)) = (proc); \
    __typeof__(user1) __tm_user1 = (user1);                             \
    __typeof__(user2) __tm_user2 = (user2);                             \
    __typeof__(user3) __tm_user3 = (user3);                             \
    void*             __tm_user4 = NULL;                                \
    hb_activate(th, tg, ((void (*)(lb_thread_t*, void*, void*, void*, void*))(__tm_proc)), ((void*)(__tm_user1)), ((void*)(__tm_user2)), ((void*)(__tm_user3)), ((void*)(__tm_user4))); \
  })

#define hb_activate_tm_4(th, tg, proc, user1, user2, user3, user4)      \
  ({                                                                    \
    void (*__tm_proc)(lb_thread_t*, __typeof__(user1), __typeof__(user2), __typeof__(user3), __typeof__(user4)) = (proc); \
    __typeof__(user1) __tm_user1 = (user1);                             \
    __typeof__(user2) __tm_user2 = (user2);                             \
    __typeof__(user3) __tm_user3 = (user3);                             \
    __typeof__(user4) __tm_user4 = (user4);                             \
    hb_activate(th, tg, ((void (*)(lb_thread_t*, void*, void*, void*, void*))(__tm_proc)), ((void*)(__tm_user1)), ((void*)(__tm_user2)), ((void*)(__tm_user3)), ((void*)(__tm_user4))); \
  })

static void hb_deactivate(void)
{
  g.hb.proc_request = NULL;
}

static void hb_proc(lb_thread_t* th, uint64_t counter LB_UNUSED)
{
  if (g.hb.proc_request) {
    if (g.hb.skip) {
      g.hb.skip = false;
    } else {
      g.hb.proc_request(th, g.hb.user_request_a, g.hb.user_request_b, g.hb.user_request_c, g.hb.user_request_d);
    }
  }
}

static void hb_start(uintptr_t interval_ms)
{
  hb_deactivate();
  lb_heartbeat_launch_tm_0(g.sw, AC, interval_ms, NULL, NULL, hb_proc);
}

static bool file_exists(char const* path)
{
  lbt_stat_t stat;
  
  intptr_t retv = lbt_lstat(path, (&(stat)));
  
  DG("sssus", "lstat('", path, "')=", LB_UI(retv), "\n");
  
  return (retv == 0);
}

static void read_fully_fd(uintptr_t fd, uint8_t* buf, uintptr_t len)
{
  uint8_t* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_read(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}

static void write_fully_fd(uintptr_t fd, uint8_t const* buf, uintptr_t len)
{
  uint8_t const* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_write(fd, buf, LB_PTRDIF(lim, buf));
    
    LB_ASSURE_GTZ(retv);
    
    buf += LB_UI(retv);
  }
}

static bool pread_fully_fd_try(uintptr_t fd, uint8_t* buf, uintptr_t len, uintptr_t off)
{
  uint8_t* lim = (buf + len);
  
  while (buf < lim) {
    intptr_t retv = lbt_pread64(fd, buf, LB_PTRDIF(lim, buf), off);
    DG("sususus", "lbt_pread64(fd, buf, ", LB_PTRDIF(lim, buf), ", ", off, ") => ", LB_U(retv), "\n");
    
    if (retv <= 0) {
      TR;
      return false;
    }
    
    uintptr_t amt = LB_UI(retv);
    
    buf += amt;
    off += amt;
  }
  
  TR;
  return true;
}

static void write_fully_file(char const* path, uintptr_t mode, uint8_t const* buf, uintptr_t len)
{
  uintptr_t fd = LBT_OK(lbt_open(path, (lbt_O_CREAT | lbt_O_TRUNC | lbt_O_WRONLY), mode));
  write_fully_fd(fd, buf, len);
  LBT_OK(lbt_close(fd));
}

static void load_config_into(char const* path, char* buf, uintptr_t siz)
{
  DG("sss", "load_config '", path, "'\n");
  
  uintptr_t fd = LBT_OK(lbt_open(path, lbt_O_RDONLY, 0000));
  
  uintptr_t len = 0;
  
  while (true) {
    intptr_t signed_amt = lbt_read(fd, (buf + len), (siz - len));
    LB_ASSURE_GEZ(signed_amt);
    uintptr_t amt = LB_UI(signed_amt);
    if (amt == 0) break;
    len += amt;
    LB_ASSURE(len < siz);
  }
  
  buf[len] = '\0';
  
  LBT_OK(lbt_close(fd));
}

static char* load_config(char const* path)
{
  char buf[SG_LOAD_CONFIG_MAXIMUM_LENGTH];
  
  load_config_into(path, buf, sizeof(buf));
  
  return lb_misc_strdup(buf, AC);
}

static void strinc(char* str)
{
  uintptr_t idx = (lb_strlen(str) - 1);
  
  while (str[idx] == '9') {
    str[idx] = '0';
    idx--;
  }
  
  str[idx]++;
}

static char const* toquad(uint32_t addr)
{
  char buf[16];
  
  uintptr_t pos = 0;
  
  pos += lb_utoa_64((buf + pos), ((addr >> 24) & 0xFF));
  buf[pos++] = '.';
  pos += lb_utoa_64((buf + pos), ((addr >> 16) & 0xFF));
  buf[pos++] = '.';
  pos += lb_utoa_64((buf + pos), ((addr >>  8) & 0xFF));
  buf[pos++] = '.';
  pos += lb_utoa_64((buf + pos), ((addr      ) & 0xFF));
  buf[pos++] = '\0';
  
  return lb_misc_strdup(buf, AC);
}

static uintptr_t ll_sk(void)
{
  return LBT_OK(lbt_socket(lbt_PF_PACKET, lbt_SOCK_DGRAM, lb_bswap_16(lbt_ETH_P_IP)));
}

static void ll_sa(lbt_sockaddr_ll_t* sa, uintptr_t if_index)
{
  LB_BZERO(*sa);
  sa->family = lbt_AF_PACKET;
  sa->protocol = lb_bswap_16(lbt_ETH_P_IP);
  sa->if_index = ((uint32_t)(if_index));
}

static void ll_sa_any(lbt_sockaddr_ll_t* sa, uintptr_t if_index)
{
  ll_sa(sa, if_index);
  sa->hw_alen = SG_MAC_ADDR_LEN;
  lb_memset(sa->hw_addr, -1UL, sizeof(sa->hw_addr));
}

static uint16_t ll_checksum(void const* buf, uintptr_t len)
{
  LB_ASSURE_EQZ((len & 1));
  
  uint16_t const* pos = ((uint16_t const*)(buf));
  uint16_t const* lim = (pos + (len >> 1));
  
  uint32_t sum = 0;
  
  LB_COMPILER_BARRIER;
  
  while (pos < lim) {
    sum += lb_bswap_16(*(pos++));
  }
  
  LB_COMPILER_BARRIER;
  
  sum = ((sum & 0xFFFF) + (sum >> 16));
  
  sum = ((~(sum)) & 0xFFFF);
  
  return ((uint16_t)(sum));
}

LB_TYPEBOTH(sg_ipv4_t)
{
  uint8_t  hdr_len;     /* = 0x45 */
  uint8_t  dsfield_ecn; /* = 0x00 */
  uint16_t ip_len;
  uint16_t id;
  uint16_t frag_offset;
  uint8_t  ttl;
  uint8_t  proto;
  uint16_t checksum;
  uint32_t src;
  uint32_t dst;
} LB_PACKED;

LB_TYPEBOTH(sg_udp_t)
{
  uint16_t srcport;
  uint16_t dstport;
  uint16_t length;
  uint16_t checksum;
} LB_PACKED;

LB_TYPEBOTH(sg_dhcp4_t)
{
  uint8_t  type;
  uint8_t  hw_type;
  uint8_t  hw_len;
  uint8_t  hops;
  uint32_t id;
  uint16_t secs;
  uint16_t flags;
  uint32_t ip_client;
  uint32_t ip_your;
  uint32_t ip_server;
  uint32_t ip_relay;
  uint8_t  hw_mac_addr[SG_MAC_ADDR_LEN];
  uint8_t  hw_addr_padding[10];
  uint8_t  server[64];
  uint8_t  file[128];
  uint32_t cookie;
} LB_PACKED;

LB_TYPEBOTH(sg_dhcp4_packet_t)
{
  sg_ipv4_t  ipv4;
  sg_udp_t   udp;
  sg_dhcp4_t dhcp4;
  uint8_t    options[4096];
} LB_PACKED;

LB_TYPEBOTH(sg_dhcp4_result_t)
{
  uint32_t addr;
  uint32_t mask;
  uint32_t gate;
  uint32_t solv;
  uint32_t serv;
};

static void dhcp_transmit(uintptr_t socket_send, uintptr_t if_index, uint8_t const* if_hwaddr, uint8_t const* optbuf, uintptr_t optlen)
{
  sg_dhcp4_packet_t pkt;
  
  LB_BZERO(pkt);
  
  pkt.ipv4.hdr_len = 0x45;
  pkt.ipv4.ip_len = ((uint16_t)(sizeof(pkt) - sizeof(pkt.options) + optlen));
  pkt.ipv4.ttl = 0xFF;
  pkt.ipv4.proto = 0x11;
  pkt.ipv4.src = 0;
  pkt.ipv4.dst = ((uint32_t)(-1UL));
  pkt.udp.srcport = 68;
  pkt.udp.dstport = 67;
  pkt.udp.length = ((uint16_t)(sizeof(sg_udp_t) + sizeof(sg_dhcp4_t) + optlen));
  pkt.dhcp4.type = 1;
  pkt.dhcp4.hw_type = 1;
  pkt.dhcp4.hw_len = SG_MAC_ADDR_LEN;
  pkt.dhcp4.id = SG_DHCP4_ID;
  lb_memcpy(pkt.dhcp4.hw_mac_addr, if_hwaddr, SG_MAC_ADDR_LEN);
  pkt.dhcp4.cookie = SG_DHCP4_MAGIC_EL;
  lb_memcpy(pkt.options, optbuf, optlen);
  
  /* do not bswap dhcp4.{id,cookie} */
  LB_BSWAP_16(pkt.udp.srcport);
  LB_BSWAP_16(pkt.udp.dstport);
  LB_BSWAP_16(pkt.udp.length);
  LB_BSWAP_16(pkt.ipv4.ip_len);
  LB_BSWAP_32(pkt.ipv4.src);
  LB_BSWAP_32(pkt.ipv4.dst);
  
  pkt.ipv4.checksum = ll_checksum((&(pkt.ipv4)), sizeof(pkt.ipv4));
  
  LB_BSWAP_16(pkt.ipv4.checksum);
  
  lbt_sockaddr_ll_t sa;
  ll_sa_any(&sa, if_index);
  DG("sms", "dhcp_tx='",         (&(pkt)), (sizeof(pkt) - sizeof(pkt.options) + optlen), "'\n");
  lbt_sendto_bypass(socket_send, (&(pkt)), (sizeof(pkt) - sizeof(pkt.options) + optlen), 0, (&(sa)), sizeof(sa));
}

#define DHCP_TRANSMIT_TOOLS                                             \
  uint8_t   buf[512];                                                   \
  uintptr_t pos = 0;                                                    \
                                                                        \
  void w0(uint8_t c)                                                    \
  {                                                                     \
    buf[pos++] = c;                                                     \
    buf[pos++] = 0;                                                     \
  }                                                                     \
                                                                        \
  void w1(uint8_t c, uint8_t v)                                         \
  {                                                                     \
    buf[pos++] = c;                                                     \
    buf[pos++] = 1;                                                     \
    buf[pos++] = v;                                                     \
  }                                                                     \
                                                                        \
  void w4(uint8_t c, uint32_t v)                                        \
  {                                                                     \
    buf[pos++] = c;                                                     \
    buf[pos++] = 4;                                                     \
    v = lb_bswap_32(v);                                                 \
    lb_memcpy((buf + pos), &v, sizeof(v));                              \
    pos += sizeof(v);                                                   \
  }

static void dhcp_discover(lb_thread_t* th LB_UNUSED, uintptr_t socket_send, uintptr_t if_index, uint8_t const* if_hwaddr)
{
  DHCP_TRANSMIT_TOOLS;
  
  /* message type = discover */
  w1(53, 1);
  
  /* parameter list */
  /* 0x01 - subnet mask */
  /* 0x03 - router */
  /* 0x1c - broadcast address */
  /* 0x36 - dhcp server address */
  w4(37, 0x01031c06);
  
  dhcp_transmit(socket_send, if_index, if_hwaddr, buf, pos);
}

static void dhcp_request(lb_thread_t* th LB_UNUSED, uintptr_t socket_send, uintptr_t if_index, uint8_t const* if_hwaddr, sg_dhcp4_result_t* result)
{
  DHCP_TRANSMIT_TOOLS;
  
  /* message type = request */
  w1(53, 3);
  
  /* requested ip address */
  w4(50, result->addr);
  
  /* server ip address */
  w4(54, result->serv);
  
  /* the end */
  w0(255);
  
  dhcp_transmit(socket_send, if_index, if_hwaddr, buf, pos);
}

static bool dhcp_receive(uint8_t* buf, uintptr_t len, uint8_t const* if_hwaddr, sg_dhcp4_result_t* result, uintptr_t* type)
{
  if (len < (sizeof(sg_dhcp4_packet_t) - sizeof(((sg_dhcp4_packet_t*)(NULL))->options))) {
    return false;
  }
  
  sg_dhcp4_packet_t* pkt;
  LB_CAST_ASGN(pkt, buf);
  
  if (!(lb_bswap_16(pkt->udp.srcport) == 67)) { TR; return false; }
  if (!(lb_bswap_16(pkt->udp.dstport) == 68)) { TR; return false; }
  if (!(pkt->dhcp4.type == 2)) { TR; return false; }
  if (!(pkt->dhcp4.id == SG_DHCP4_ID)) { TR; return false; }
  if (!(lb_memcmp(pkt->dhcp4.hw_mac_addr, if_hwaddr, SG_MAC_ADDR_LEN))) { TR; return false; }
  if (!(pkt->dhcp4.cookie == SG_DHCP4_MAGIC_EL)) { TR; return false; }
  
  LB_BZERO(*result);
  
  result->addr = lb_bswap_32(pkt->dhcp4.ip_your);
  
  uint8_t* head = (pkt->options);
  uint8_t* tail = (buf + len);
  
  while (LB_PTRDIF(tail, head) > 2) {
    uint8_t code = *(head++);
    uint8_t size = *(head++);
    
    if (LB_PTRDIF(tail, head) < size) break;
    
    if (code == 255) break;
    
    if ((code == 0x35) && (size == 1)) *type = *head;
    if ((code == 0x01) && (size == 4)) result->mask = lb_bswap_32((*((uint32_t*)(head))));
    if ((code == 0x03) && (size == 4)) result->gate = lb_bswap_32((*((uint32_t*)(head))));
    if ((code == 0x06) && (size >= 4)) result->solv = lb_bswap_32((*((uint32_t*)(head))));
    if ((code == 0x36) && (size == 4)) result->serv = lb_bswap_32((*((uint32_t*)(head))));
    
    head += size;
  }
  
  return true;
}

static bool dhcp_offer(uint8_t* buf, uintptr_t len, uint8_t const* if_hwaddr, sg_dhcp4_result_t* result)
{
  uintptr_t type;
  
  if (dhcp_receive(buf, len, if_hwaddr, result, (&(type)))) {
    return (type == (2 /* Offer */));
  }
  
  return false;
}

static bool dhcp_ack(uint8_t* buf, uintptr_t len, uint8_t const* if_hwaddr, sg_dhcp4_result_t* result)
{
  sg_dhcp4_result_t inner;
  uintptr_t type;
  
  if (dhcp_receive(buf, len, if_hwaddr, (&(inner)), (&(type)))) {
    return ((type == (5 /* ACK */)) && (inner.addr == result->addr));
  }
  
  return false;
}

static void do_dhcp__hb_discover(lb_thread_t* th, uintptr_t socket_send, uintptr_t if_index, uint8_t const* if_hwaddr)
{
  TR;
  dhcp_discover(th, socket_send, if_index, if_hwaddr);
}

static void do_dhcp__hb_request(lb_thread_t* th, uintptr_t socket_send, uintptr_t if_index, uint8_t const* if_hwaddr, sg_dhcp4_result_t* result)
{
  TR;
  dhcp_request (th, socket_send, if_index, if_hwaddr, result);
}

static void do_dhcp(lb_thread_t* th, sg_dhcp4_result_t* result)
{
  TR;
  char const* if_name = load_config("sg_if_name");
  uintptr_t   if_index;
  uint8_t*    if_hwaddr = ((uint8_t*)(lb_alloc(g.ac, SG_MAC_ADDR_LEN)));
  TR;
  uintptr_t socket_scan = LBT_OK(lbt_socket(lbt_PF_INET, lbt_SOCK_RAW, lbt_IPPROTO_RAW));
  TR;
  lbt_ifreq_t ifreq;
  TR;
  void ifreq_prepare(void)
  {
    LB_BZERO(ifreq);
    lb_memcpy(ifreq.name, if_name, (lb_strlen(if_name) + 1));
  }
  TR;
  /*
    bring up interface and determine interface index.
  */
  {
    /*
      first assign the address 0.0.0.0 to make sure the interface
      comes up address-less.
    */
    while (true) {
      ifreq_prepare();
      {
        lbt_sockaddr_in_t sa;
        sa.family = lbt_AF_INET;
        sa.host = 0;
        lb_memcpy(ifreq.misc.u8, (&(sa)), sizeof(sa));
      }
      if (lbt_ioctl_bypass(socket_scan, lbt_SIOCSIFADDR, LB_U((&(ifreq)))) != 0) {
        DG("s", "interface unavailable, trying again soon ...\n");
        lbt_nanosleep_bypass(0, 100000000 /* 100ms */);
        continue;
      }
      break;
    }
    TR;
    ifreq_prepare();
    ifreq.misc.u16[0] = (lbt_IFF_UP | lbt_IFF_BROADCAST | lbt_IFF_RUNNING | lbt_IFF_MULTICAST);
    LBT_OK(lbt_ioctl_bypass(socket_scan, lbt_SIOCSIFFLAGS, LB_U((&(ifreq)))));
    TR;
    ifreq_prepare();
    LBT_OK(lbt_ioctl_bypass(socket_scan, lbt_SIOCGIFINDEX, LB_U((&(ifreq)))));
    if_index = lb_misc_narrow_64_ptr(ifreq.misc.u64[0]);
    TR;
    ifreq_prepare();
    LBT_OK(lbt_ioctl_bypass(socket_scan, lbt_SIOCGIFHWADDR, LB_U((&(ifreq)))));
    lb_memcpy(if_hwaddr, (ifreq.misc.u8 + 2), sizeof(if_hwaddr));
  }
  TR;
  uint8_t const* if_hwaddr_const = ((uint8_t const*)(if_hwaddr));
  TR;
  /*
    wait for the interface's operstate to say "up".
  */
  {
    /* sg_if_fn_o should contain a string like "/sys/class/net/eth0/operstate" */
    char const* if_fn_operstate = load_config("sg_if_fn_o");
    TR;
    while (true) {
      char buf[16];
      buf[0] = '\0';
      load_config_into(if_fn_operstate, buf, sizeof(buf));
      TR;
      if (buf[0] == 'u') { /* u = "up" */
        break;
      }
      TR;
      lbt_nanosleep_bypass(0, 100000000 /* 100ms */);
    }
  }
  TR;
  PV(if_index);
  DG("sms", "if_hwaddr='", if_hwaddr, sizeof(if_hwaddr), "'\n");
  TR;
  /*
    bind sending and receiving sockets.
  */
  TR;
  uintptr_t socket_recv = ll_sk();
  
  {
    lbt_sockaddr_ll_t sa;
    ll_sa(&sa, if_index);
    LBT_OK(lbt_bind(socket_recv, (&(sa)), sizeof(sa)));
  }
  
  uintptr_t socket_send = ll_sk();
  
  {
    lbt_sockaddr_ll_t sa;
    ll_sa_any(&sa, if_index);
    LBT_OK(lbt_bind(socket_send, (&(sa)), sizeof(sa)));
  }
  
  /*
    declare result and define receive loop.
  */
  
  uintptr_t deaf = 0; // set to nonzero value to test retry
  
  void recv_loop(bool (*proc)(uint8_t*, uintptr_t, uint8_t const*, sg_dhcp4_result_t*))
  {
    while (true) {
      uint8_t buf[SG_DHCP4_RESPONSE_SIZE];
      
      LB_BZERO(buf);
      
      lb_io_set_nonblocking(socket_recv);
      
      intptr_t retv = lbt_recvfrom_bypass(socket_recv, buf, sizeof(buf), 0, NULL, 0);
      
      if (LBI_IO_TRYAGAIN) {
        lb_switch_epoll_wait(th, socket_recv, lbt_EPOLLIN);
        continue;
      }
      
      if (retv <= 0) {
        continue;
      }
      
      uintptr_t len = LB_UI(retv);
      
      DG("sms", "dhcp_rx='", buf, len, "'\n");
      
      if (deaf) {
        TR;
        deaf--;
        continue;
      }
      
      if (proc(buf, len, if_hwaddr, result)) {
        break;
      }
    }
  }
  
  hb_activate_tm_3(th, true, do_dhcp__hb_discover, socket_send, if_index, if_hwaddr_const);
  recv_loop(dhcp_offer);
  hb_deactivate();
  
  hb_activate_tm_4(th, true, do_dhcp__hb_request, socket_send, if_index, if_hwaddr_const, result);
  recv_loop(dhcp_ack);
  hb_deactivate();
  
  LBT_OK(lbt_close(socket_send));
  LBT_OK(lbt_close(socket_recv));
  
  DG("sssssssssss", "addr=", toquad(result->addr), ", mask=", toquad(result->mask), ", gate=", toquad(result->gate), ", solv=", toquad(result->solv), ", serv=", toquad(result->serv), "\n");
  
  /*
    now configure the interface with the address.
  */
  {
    ifreq_prepare();
    {
      lbt_sockaddr_in_t sa;
      sa.family = lbt_AF_INET;
      sa.host = lb_bswap_32(result->addr);
      lb_memcpy(ifreq.misc.u8, (&(sa)), sizeof(sa));
    }
    LBT_OK(lbt_ioctl_bypass(socket_scan, lbt_SIOCSIFADDR, LB_U((&(ifreq)))));
    
    ifreq_prepare();
    {
      lbt_sockaddr_in_t sa;
      LB_BZERO(sa);
      sa.family = lbt_AF_INET;
      sa.host = lb_bswap_32(result->mask);
      lb_memcpy(ifreq.misc.u8, (&(sa)), sizeof(sa));
    }
    LBT_OK(lbt_ioctl_bypass(socket_scan, lbt_SIOCSIFNETMASK, LB_U((&(ifreq)))));
    
    /*
      and routing.
    */
    {
      struct {
        unsigned long     rt_pad1;
        lbt_sockaddr_in_t rt_dst;
        lbt_sockaddr_in_t rt_gateway;
        lbt_sockaddr_in_t rt_genmask;
        unsigned short    rt_flags;
        short             rt_pad2;
        unsigned long     rt_pad3;
        void             *rt_pad4;
        short             rt_metric;
        char             *rt_dev;
        unsigned long     rt_mtu;
        unsigned long     rt_window;
        unsigned short    rt_irtt;
      } LB_PACKED rt;
      
      LB_BZERO(rt);
      
      rt.rt_dst.family     = lbt_AF_INET;
      rt.rt_gateway.family = lbt_AF_INET;
      rt.rt_gateway.host   = lb_bswap_32(result->gate);
      rt.rt_genmask.family = lbt_AF_INET;
      rt.rt_flags          = (lbt_RTF_UP | lbt_RTF_GATEWAY);
      rt.rt_metric         = 102;
      
      LBT_OK(lbt_ioctl_bypass(socket_scan, lbt_SIOCADDRT, LB_U((&(rt)))));
    }
  }
  
  LBT_OK(lbt_close(socket_scan));
}

static uintptr_t do_dns_send(uintptr_t socket, char const* host)
{
  static uint8_t const cooked_request_prefix[] = { 0x73, 0x67, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
  static uint8_t const cooked_request_suffix[] = { 0x00, 0x00, 0x01, 0x00, 0x01 };
  
  uint8_t buf[SG_DNS_REQUEST_SIZE];
  uintptr_t len = 0;
  
  lb_memcpy((buf + len), cooked_request_prefix, sizeof(cooked_request_prefix));
  len += sizeof(cooked_request_prefix);
  
  char const* host_lim = (host + lb_strlen(host));
  while (host < host_lim) {
    char const* off = ((char const*)(lb_memchr(host, '.', LB_PTRDIF(host_lim, host))));
    if (!off) off = host_lim;
    uintptr_t spn = LB_PTRDIF(off, host);
    buf[len++] = ((uint8_t)(spn));
    lb_memcpy((buf + len), host, spn);
    len += spn;
    host = (off + 1);
  }
  
  lb_memcpy((buf + len), cooked_request_suffix, sizeof(cooked_request_suffix));
  len += sizeof(cooked_request_suffix);
  
  DG("sms", "dns_tx='", buf, len, "'\n");
  
  LB_ASSURE((LB_UI(lbt_sendto_bypass(socket, buf, len, 0, NULL, 0)) == len));
  
  return len;
}

static void do_dns__hb_send(lb_thread_t* th LB_UNUSED, uintptr_t socket, char const* host)
{
  do_dns_send(socket, host);
}

static void do_dns(lb_thread_t* th, char const* host, uint32_t* addr_host)
{
  static uint8_t const cooked_pattern[] = { 0xc0, 0x0c, 0x00, 0x01, 0x00, 0x01 };
  
  uintptr_t socket = LBT_OK(lbt_socket(lbt_PF_INET, lbt_SOCK_DGRAM, lbt_IPPROTO_IP));
  
  {
    lbt_sockaddr_in_t sa;
    LB_BZERO(sa);
    sa.family = lbt_AF_INET;
    sa.port = lb_bswap_16(53);
    sa.host = lb_bswap_32(SG_DNS_SERVER_IP);
    LBT_OK(lbt_connect(socket, &sa, sizeof(sa)));
  }
  
  hb_activate_tm_2(th, true, do_dns__hb_send, socket, host);
  
  uintptr_t deaf = 0; // set to nonzero value to test retry
  
  while (true) {
    uint8_t buf[SG_DNS_RESPONSE_SIZE];
    
    LB_BZERO(buf);
    
    lb_io_set_nonblocking(socket);
    
    intptr_t retv = lbt_recvfrom_bypass(socket, buf, sizeof(buf), 0, NULL, 0);
    
    if (LBI_IO_TRYAGAIN) {
      lb_switch_epoll_wait(th, socket, lbt_EPOLLIN);
      continue;
    }
    
    if (retv <= 0) {
      continue;
    }
    
    uintptr_t len = LB_UI(retv);
    
    DG("sms", "dns_rx='", buf, len, "'\n");
    
    if (deaf) {
      TR;
      deaf--;
      continue;
    }
    
    uint8_t* off;
    
    if ((off = ((uint8_t*)(lb_memmem(buf, len, cooked_pattern, sizeof(cooked_pattern))))) != NULL) {
      if ((off + 12 + 4) <= (buf + len)) {
        lb_memcpy(addr_host, (off + 12), 4);
        (*(addr_host)) = lb_bswap_32((*(addr_host)));
        break;
      }
    }
  }
  
  hb_deactivate();
  
  LBT_OK(lbt_close(socket));
}

static uint8_t* do_http(uint32_t host, char const* cooked_request, uintptr_t size)
{
  uintptr_t socket = LBT_OK(lbt_socket(lbt_PF_INET, lbt_SOCK_STREAM, lbt_IPPROTO_IP));
  
  {
    lbt_sockaddr_in_t sa;
    LB_BZERO(sa);
    sa.family = lbt_AF_INET;
    sa.port = lb_bswap_16(((uint16_t)(lb_atou_64(load_config("sg_http_port")))));
    sa.host = lb_bswap_32(host);
    LBT_OK(lbt_connect(socket, (&(sa)), sizeof(sa)));
  }
  
  write_fully_fd(socket, ((uint8_t const*)(cooked_request)), lb_strlen(cooked_request));
  
  uintptr_t lim = (SG_HTTP_RESPONSE_SIZE + size);
  uint8_t*  buf = ((uint8_t*)(lb_alloc(AC, lim)));
  uintptr_t len = 0;
  
  uint8_t*  sta = NULL;
  
  while (true) {
    if (!(len < lim)) {
      return NULL;
    }
    
    intptr_t retv = lbt_read(socket, (buf + len), (lim - len));
    
    if (!(retv > 0)) {
      PV(retv);
      return NULL;
    }
    
    len += LB_UI(retv);
    
    if (!sta) {
      sta = ((uint8_t*)(lb_memmem(buf, len, "\r\n\r\n", 4)));
      if (sta) sta += 4;
    }
    
    if ((sta) && (LB_PTRDIF((buf + len), sta) >= size)) {
      break;
    }
  }
  
  LBT_OK(lbt_close(socket));
  
  return sta;
}

static void success(uint8_t* file, uintptr_t size)
{
  write_fully_file("./sg_pl_ini", 0700, file, size);
  
  lbt_sigtimedwait_simple_SIGPIPE_bypass();
  lbt_unblock_signal_simple_SIGPIPE();
  
  if (file_exists("sg_do_exec")) {
    DG("s", "execve!\n");
    char const* argv_pass[] = { "/sg_pl_ini", NULL };
    lbt_execve_bypass("/sg_pl_ini", argv_pass, g.envp);
    DG("s", "execve failed!!!\n");
  } else {
    /*
      we found something, but sg_do_exec is not set. do not continue
      to try other methods. just quit.
     */
    
    lbt_exit_simple(0);
    
    LB_ILLEGAL;
  }
}

static void try_with_file(uintptr_t size, uint8_t* file)
{
  lb_sha256_state_t stas;
  uint64_t          stas_total = 0;
  
  lb_sha256_init(&stas);
  lb_sha256_calc_len(&stas, &stas_total, file, size, true, 1);
  LB_ASSURE(stas_total == size);
  
  char out[lb_sha256_dsiz];
  lb_sha256_dump(&stas, out);
  
  char* exp = load_config("sg_pl_sum");
  
  uintptr_t const sum_len = (256/8*2);
  LB_ASSURE(lb_strlen(out) == sum_len);
  LB_ASSURE(lb_strlen(exp) == sum_len);
  
  if (lb_memcmp(out, exp, sum_len)) {
    success(file, size);
  } else {
    LB_ILLEGAL;
  }
}

static void network_thread(lb_thread_t* th)
{
  TR;
  if (file_exists("sg_do_dhcp")) {
    LB_ALLOC_DECL(sg_dhcp4_result_t, result, AC);
    do_dhcp(th, result);
  }
  TR;
  uint32_t addr_host = 0;
  do_dns(th, load_config("sg_dns_host"), &addr_host);
  DG("ss", toquad(addr_host), "\n");
  TR;
  uintptr_t size = lb_misc_narrow_64_ptr(lb_atou_64(load_config("sg_pl_siz")));
  uint8_t*  file = do_http(addr_host, load_config("sg_pl_req"), size);
  TR;
  if (file) {
    TR;
    try_with_file(size, file);
  }
  TR;
}

static void initialize_mount_proc_sys_dev(void)
{
  if (file_exists("sg_do_mount")) {
    LBT_OK(lbt_mkdir_bypass("/proc", 0700));
    LBT_OK(lbt_mount_bypass("none", "/proc", "proc", lbt_MS_SILENT, NULL));
    LBT_OK(lbt_mkdir_bypass("/sys", 0700));
    LBT_OK(lbt_mount_bypass("none", "/sys", "sysfs", lbt_MS_SILENT, NULL));
    //LBT_OK(lbt_mkdir_bypass("/dev", 0700)); // always /dev already exists
    LBT_OK(lbt_mount_bypass("none", "/dev", "devtmpfs", lbt_MS_SILENT, NULL));
  }
}

static void initialize_load_kernel_modules(void)
{
  char str[] = { 'm', '1', '0', '0', 0 };
  
  //DG("us", LB_U(str), "\n");
  //DG("sss", "checking '", str, "'\n");
  while (file_exists(str)) {
    DG("sss", "loading '", str, "'\n");
    
    uintptr_t fd = LBT_OK(lbt_open(str, lbt_O_RDONLY, 0000));

    /*
      EEXIST is likely because the scripts dumbly attempt to load all
      dependency modules all the time.
    */
    {
      intptr_t retv = lbt_finit_module(fd, "", 0);
      LB_ASSURE(((retv == 0) || (retv == (-lbt_EEXIST))));
    }
    
    LBT_OK(lbt_close(fd));
    
    strinc(str);
    
    //DG("sss", "checking '", str, "'\n");
  }
}

static void initialize_drive_settle(void)
{
  uintptr_t sec = lb_misc_narrow_64_ptr(lb_atou_64(load_config("sg_ds_s")));
  lbt_nanosleep_bypass(sec, 0);
}

#define RID_SIZ ((256/8)*2)

static void initialize_try_one_drive(uintptr_t off, uintptr_t siz, uint8_t* rid, uintptr_t fd)
{
  uint8_t riv[RID_SIZ];
  
  PV(fd);
  PV((off + siz - sizeof(riv)));
  
  if (pread_fully_fd_try(fd, riv, sizeof(riv), (off + siz - sizeof(riv)))) {
    DG("s", "got rid!\n");
    
    if (lb_memcmp(riv, rid, sizeof(riv))) {
      DG("s", "rid match!\n");
      
      uint8_t* buf = ((uint8_t*)(lb_alloc(AC, siz)));
      
      if (pread_fully_fd_try(fd, buf, siz, off)) {
        DG("s", "got file!\n");
        
        try_with_file(siz, buf);
      }
    }
  }
}

static void initialize_try_all_drives(void)
{
  uintptr_t off = lb_misc_narrow_64_ptr(lb_atou_64(load_config("sg_pl_off")));
  uintptr_t siz = lb_misc_narrow_64_ptr(lb_atou_64(load_config("sg_pl_siz")));
  
  LB_ASSURE((siz >= RID_SIZ));
  
  uint8_t rid[RID_SIZ];
  
  {
    uintptr_t fd = LBT_OK(lbt_open("sg_pl_rid", (lbt_O_RDONLY), 0000));
    read_fully_fd(fd, rid, sizeof(rid));
    LBT_OK(lbt_close(fd));
  }
  
  char str[] = { 'b', '1', '0', '0', 0 };
  
  while (file_exists(str)) {
    DG("sss", "trying '", str, "'\n");
    
    intptr_t retv = lbt_open(str, lbt_O_RDONLY, 0000);
    
    if (retv >= 0) {
      DG("s", "it's open!\n");
      
      uintptr_t fd = LB_UI(retv);
      
      initialize_try_one_drive(off, siz, rid, fd);
    }
    
    strinc(str);
  }
}

static void initialize_emmc_probe_workaround(void)
{
  uintptr_t retv_fork = LBT_OK(lbt_fork_bypass());
  
  if (retv_fork == 0) {
    {
      /* child */
      
      intptr_t fd;
      
      while (!((fd = lbt_open("/dev/mmcblk0", lbt_O_RDONLY, 0)) >= 0)) {
        lbt_nanosleep_bypass(0, 100000000 /* 100ms */);
      }
      
      uint8_t buf[512];
      
      if (LB_UI(lbt_read(LB_U(fd), buf, sizeof(buf))) == sizeof(buf)) {
        write_fully_file("sg_emmc_probe_good", 0777, buf, 0);
      }
      
      lbt_exit_simple(0);
      
      LB_ILLEGAL;
    }
  } else {
    {
      /* parent */
      
      for (uintptr_t i = 0; i < 30; i++) {
        if (lbt_wait_simple_bypass(retv_fork) != 0) {
          break;
        }
        
        lbt_nanosleep_bypass(0, 100000000 /* 100ms */);
      }
      
      if (!(file_exists("sg_emmc_probe_good"))) {
        // try /proc/sysrq-trigger reboot
        {
          intptr_t fd = lbt_open("/proc/sysrq-trigger", lbt_O_WRONLY, 0);
          
          if (fd >= 0) {
            lbt_write(LB_U(fd), ((unsigned char const*)("b")), 1);
          }
        }
        
        // try reboot syscall
        lbt_reboot_simple_bypass();
        
        // well drats
        LB_ILLEGAL;
      }
    }
  }
}

static void initialize_fixes(void)
{
  if (file_exists("sg_do_emmc_probe_workaround")) {
    initialize_emmc_probe_workaround();
  }
}

static void initialize(void)
{
  initialize_mount_proc_sys_dev();
  initialize_load_kernel_modules();
  initialize_drive_settle();
  initialize_fixes();
  initialize_try_all_drives();
}

LB_MAIN_SPEC
{
  LB_BZERO(g);
  
  g.argv = argv;
  g.envp = envp;
  
  lbt_block_signal_simple_SIGPIPE();
  
  lb_sbrk_t sb_;
  lb_sbrk_t* sb = (&(sb_));
  lb_sbrk_initialize(sb);
  
  lb_alloc_t ac_;
  g.ac = (&(ac_));
  lb_alloc_initialize(g.ac, sb);
  
  lb_switch_t sw_;
  g.sw = (&(sw_));
  lb_switch_initialize(g.sw, g.ac);
  TR;
  hb_start(lb_misc_narrow_64_ptr(lb_atou_64(load_config("sg_hb_ms"))));
  TR;
  initialize();
  TR;
  lb_switch_create_thread_tm_0(g.sw, network_thread);
  TR;
  lb_switch_event_loop(g.sw, NULL, NULL);
  TR;
  LB_ABORT;
}
