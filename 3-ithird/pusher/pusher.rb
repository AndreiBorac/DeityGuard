#!/usr/bin/env bash
# -*- mode: ruby; -*-

NIL2=\
=begin
set -o xtrace
set -o errexit
set -o nounset
set -o pipefail

PATH="$(echo {/usr{/local,},}/{s,}bin | tr ' ' ':')"

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

THID_CLIENT_HOST_FOR_CHANNEL =\
{
  1 => "10.183.215.102",
  2 => "10.183.215.202",
  3 => "10.183.215.302",
  4 => "10.183.215.402",
  5 => "10.183.215.502",
  6 => "10.183.215.602",
  7 => "10.183.215.702",
  8 => "10.183.215.802",
  9 => "10.183.215.902",
};

THID_CLIENT_HOST = THID_CLIENT_HOST_FOR_CHANNEL[$channel];

THID_PORT = 18054;

THID_COMMAND_RESET = 1;
THID_COMMAND_CHUNK = 2;
THID_COMMAND_FINAL = 3;

THID_UDP_PAYLOAD_SIZE = 1472;
THID_CHUNK_SIZE = (THID_UDP_PAYLOAD_SIZE - 32 - 1 - 1 - 4 - 8);
THID_ZONE_CHUNKS = 16384;

REPEAT_FACTOR = 3;

REPEAT_FACTOR_COMMANDS = (REPEAT_FACTOR * THID_ZONE_CHUNKS);

$sok = UDPSocket.open;

def remit_bh(data)
  csum = (Digest::SHA256.digest(data));
  
  #$stderr.puts("csum=#{csum.inspect}");
  #$stderr.puts("data=#{data.inspect}");
  
  data = (csum + data);
  
  $sok.send(data, 0, THID_CLIENT_HOST, THID_PORT);
end

$global_ctr = 0;

def remit_hl(cmd, gen, idx, buf)
  remit_bh([ cmd, gen, idx, ($global_ctr += 1), buf ].pack("CCL>Q>a*"));
end

def remit_hl_rf(cmd, gen, idx, buf)
  (1..REPEAT_FACTOR_COMMANDS).each{
    remit_hl(cmd, gen, idx, buf);
  };
end

$global_gen = 0;

def handle(zon, len)
  gen = ($global_gen += 1);
  
  (1..REPEAT_FACTOR).each{
    (0...THID_ZONE_CHUNKS).each{|idx|
      remit_hl(THID_COMMAND_CHUNK, gen, idx, zon[idx]);
    };
  };
  
  if (len > 0)
    remit_hl_rf(THID_COMMAND_FINAL, (gen + 1), len, EMPTY_CHUNK);
  end
end

EMPTY_CHUNK = "".ljust(THID_CHUNK_SIZE);

def pad_up(zon)
  while (zon.length < THID_ZONE_CHUNKS)
    zon << EMPTY_CHUNK;
  end
  
  return zon;
end

def main
  # optimistically assume the last transfer completed or this one
  # packet gets through - it wastes too much time to repeat this
  # safety packet
  remit_hl(THID_COMMAND_FINAL, 0, 0, EMPTY_CHUNK);
  
  remit_hl_rf(THID_COMMAND_RESET, 0, 0, EMPTY_CHUNK);
  
  zon = [];
  
  while ((buf = STDIN.read(THID_CHUNK_SIZE)).nil?.!)
    if (buf.length == THID_CHUNK_SIZE)
      zon << buf;
      
      if (zon.length == THID_ZONE_CHUNKS)
        handle(zon, -1);
        
        zon.clear;
      end
    else
      amt = ((zon.length * THID_CHUNK_SIZE) + buf.length);
      
      zon << buf.ljust(THID_CHUNK_SIZE);
      
      handle(pad_up(zon), amt);
      
      return;
    end
  end
  
  amt = (zon.length * THID_CHUNK_SIZE);
  
  handle(pad_up(zon), amt);
end

main;
