#!/usr/bin/env bash
# -*- mode: ruby; -*-

NIL2=\
=begin
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

PATH="$(echo {/usr{/local,},}/{s,}bin | tr ' ' ':')"

if [ ! -f /tmp/ithird_udpcap ]
then
  cat    >/tmp/ithird_udpcap.c <<'EOF'
#include <stdbool.h>
#include <inttypes.h>
#include <string.h>
#include <stdio.h>

#include <stdlib.h>

#include <unistd.h>
#include <fcntl.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/mman.h>

#include <arpa/inet.h>

#include <pthread.h>

#define UNUSED __attribute__((unused))

#define assure(what_expr)                                               \
  if (!(what_expr)) assure_failed(__FILE__, __LINE__, #what_expr);

static void assure_failed(char const* file, int line, char const* expr)
{
  fprintf(stderr, "assure failed: (%s)[%d]: %s was FALSE\n", file, line, expr);
  exit(1);
  while (1);
}

#define MAX_PKT_LEN 1472

// known too low values: 32768
#define MAX (8192*8)

typedef struct
{
  uint32_t len;
  uint8_t  buf[MAX_PKT_LEN];
}
Packet;

typedef struct
{
  uintptr_t off;
  uintptr_t lim;
  Packet*   ptr[MAX];
}
Queue;

typedef struct
{
  pthread_mutex_t guard;
  pthread_cond_t  event;
  
  Queue free;
  Queue pend;
  
  Packet prealloc[(MAX - 1)];
}
G;

G g;

static inline uintptr_t increment(uintptr_t off)
{
  return ((off + 1) & (MAX - 1));
}

static inline bool isempty_lowlevel(Queue* queue)
{
  return (queue->off == queue->lim);
}

static void enqueue(Queue* queue, Packet* packet, bool use_event)
{
  pthread_mutex_lock((&(g.guard)));
  {
    queue->ptr[queue->lim] = packet;
    queue->lim = increment(queue->lim);
    if (use_event) pthread_cond_signal((&(g.event)));
  }
  pthread_mutex_unlock((&(g.guard)));
}

static Packet* dequeue(Queue* queue, bool use_event)
{
  Packet* packet;
  
  pthread_mutex_lock((&(g.guard)));
  {
    while (isempty_lowlevel(queue)) {
      if (use_event) {
        pthread_cond_wait((&(g.event)), (&(g.guard)));
      } else {
        packet = NULL;
        goto out;
      }
    }
    
    packet = queue->ptr[queue->off];
    queue->off = increment(queue->off);
  }
out:
  pthread_mutex_unlock((&(g.guard)));
  
  return packet;
}

void* main_writer(void* ignored UNUSED)
{
  while (true) {
    Packet* packet;
    
    assure((packet = dequeue((&(g.pend)), true)) != NULL);
    assure(write(1, (&(packet->len)), sizeof(packet->len)) == sizeof(packet->len));
    assure(write(1, packet->buf, packet->len) == packet->len);
    enqueue((&(g.free)), packet, false);
  }
}

int main(int argc, char const* const* argv)
{
  {
    pthread_mutex_init((&(g.guard)), NULL);
    pthread_cond_init((&(g.event)), NULL);
    
    g.free.off = g.free.lim = 0;
    g.pend.off = g.pend.lim = 0;
    
    for (uintptr_t i = 0; i < (MAX - 1); i++) {
      enqueue((&(g.free)), (&(g.prealloc[i])), false);
    }
  }
  
  unsigned int channel;
  
  {
    assure(argc == 2);
    assure(strlen(argv[1]) == 1);
    assure(('1' <= argv[1][0]) && (argv[1][0] <= '9'));
    channel = ((unsigned int)(argv[1][0] - '0'));
  }
  
  int sok;
  
  {
    assure((sok = socket(AF_INET, SOCK_DGRAM, 0)) >= 0);
  }
  
  {
    unsigned int host;
    
    host = ((((((10 << 8) + 183) << 8) + 215) << 8) + ((100 * channel) + 2));
    
    struct sockaddr_in sin;
    
    memset((&sin), 0, sizeof(sin));
    
    sin.sin_family = AF_INET;
    sin.sin_addr.s_addr = htonl(host);
    sin.sin_port = htons(18054);
    
    assure(bind(sok, ((struct sockaddr*)(&sin)), sizeof(sin)) >= 0);
  }
  
  {
    pthread_t ign;
    assure(pthread_create((&ign), NULL, main_writer, NULL) == 0);
  }
  
  if (mlockall((MCL_CURRENT | MCL_FUTURE)) == 0) {
    fprintf(stderr, "mlockall success\n");
  } else {
    fprintf(stderr, "mlockall failed probably because you are not root continuing anyways\n");
  }
  
  fprintf(stderr, "ready ...\n");
  
  struct timespec ts_enter, ts_leave;
  
  long latency_worst = 0;
  
  clock_gettime(CLOCK_MONOTONIC, (&ts_enter));
  
  while (true) {
    Packet* packet;
    
    assure((packet = dequeue((&(g.free)), false)) != NULL);
    
    clock_gettime(CLOCK_MONOTONIC, (&ts_leave));
    
    {
      if (ts_leave.tv_sec == ts_enter.tv_sec) {
        long diff = (ts_leave.tv_nsec - ts_enter.tv_nsec);
        
        if (diff > latency_worst) {
          latency_worst = diff;
          
          fprintf(stderr, "lat %lu\n", latency_worst);
        }
      }
    }
    
    ssize_t len;
    
    assure((len = recv(sok, packet->buf, MAX_PKT_LEN, 0)) >= 0);
    
    clock_gettime(CLOCK_MONOTONIC, (&ts_enter));
    
    packet->len = ((uint32_t)(len));
    
    enqueue((&(g.pend)), packet, true);
  }
}
EOF
  
  gcc -W{error,all,extra,conversion} -O2 -o /tmp/ithird_udpcap{,.c} -lpthread
fi

exec env -i PATH="$PATH" ruby -E BINARY:BINARY -e 'require("'"$0"'")' -- "$@"

exit 1
=end

require("digest");
require("socket");

def non_nil(x)
  raise if (x.nil?);
  return x;
end

$channel = non_nil(ARGV[0]).to_i;
raise if (!((1 <= $channel) && ($channel <= 9)));

#$dir = non_nil(ARGV[1]);
#raise if (!(File.directory?($dir)));

def run(cmd)
  #$stderr.puts("system: #{cmd.inspect}");
  
  raise if (!(system(cmd)));
end

THID_COMMAND_RESET = 1;
THID_COMMAND_CHUNK = 2;
THID_COMMAND_FINAL = 3;

THID_UDP_PAYLOAD_SIZE = 1472;
THID_CHUNK_SIZE = (THID_UDP_PAYLOAD_SIZE - 32 - 1 - 1 - 4 - 8);
THID_ZONE_CHUNKS = 16384;

$global_ctr = 0;
$global_zon = (1..THID_ZONE_CHUNKS).map{ (1..THID_CHUNK_SIZE).map{ "0"; }.join; };
$global_map = nil;
$global_iof = nil;
$global_gen = nil;

def handle_payload(data)
  cmd, gen, idx, ctr, buf = data.unpack("CCL>Q>a*");
  
  #$stderr.puts("cmd=#{cmd.inspect}, gen=#{gen.inspect}, idx=#{idx.inspect}, buf.length=#{buf.length.inspect}");
  
  if (ctr != ($global_ctr += 1))
    $stderr.puts("counter jump: found #{ctr} != expected #{$global_ctr} (#{ctr - $global_ctr} missed packets)");
    
    $global_ctr = ctr;
  end
  
  raise if (!(buf.length == THID_CHUNK_SIZE));
  
  case cmd
  when THID_COMMAND_RESET
    if ($global_iof.nil?)
      $stderr.puts("reset!");
      
      $global_map = (1..THID_ZONE_CHUNKS).map{ false; };
      $global_iof = IO.popen("tar -x --verbose --no-overwrite-dir ; echo \"tar_exit_$?\" >&2", "wb");
      $global_gen = 1;
    end
    
  when THID_COMMAND_CHUNK
    if ($global_iof.nil?.!)
      if (gen != $global_gen)
        raise("fatal generation skip (gen=#{gen} global_gen=#{$global_gen})") if (gen != ($global_gen + 1));
        raise("fatal generation incomplete (gen=#{gen})") if (!($global_map.inject(true){|s, i| (s && i); }));
        
        out = $global_zon.join;
        $global_map = (1..THID_ZONE_CHUNKS).map{ false; };
        $global_iof.write(out);
        $global_gen = gen;
      end
      
      raise if (!((0 <= idx) && (idx < THID_ZONE_CHUNKS)));
      
      $global_zon[idx] = buf;
      $global_map[idx] = true;
    end
    
  when THID_COMMAND_FINAL
    if ($global_iof.nil?.!)
      $stderr.puts("final!");
      
      raise("fatal generation skip (gen=#{gen} global_gen=#{$global_gen})") if (gen != ($global_gen + 1));
      raise("fatal generation incomplete (gen=#{gen})") if (!($global_map.inject(true){|s, i| (s && i); }));
      
      out = $global_zon.join[0...idx];
      $global_iof.write(out);
      $global_iof.close;
      $global_iof = nil;
    end
    
  else
    raise;
    
  end
end

def handle_outer(data)
  csum = data[0...32];
  data = data[32..-1];
  
  if (Digest::SHA256.digest(data) == csum)
    handle_payload(data);
  else
    $stderr.puts("invalid packet: bad checksum");
  end
end

$niceness = "";

if (Process::UID.eid == 0)
  $niceness = "nice -n -20 ";
end

IO.popen("#{$niceness}/tmp/ithird_udpcap #{$channel}"){|inp|
  loop{
    len = inp.sysread(4).unpack("L")[0];
    buf = inp.sysread(len);
    
    raise if (!(buf.length == len));
    
    handle_outer(buf);
  };
};
