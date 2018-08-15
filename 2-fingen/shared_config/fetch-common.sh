# offset of first GPT partition
COMMON_CACHE_PARTITION_OFFSET="$(( (2048*512) ))"

# the "clear zone" is always kept as zeroes, for multiple reasons:
# 
# (1) to prevent the cache partition from accidentially containing a
# magic value that would cause it to be recognized as storing some
# other kind of data for some other purpose. before adding the veysp
# target, the clear zone was 1MiB.
# 
# (2) on veysp, the first 8MiB of the EMMC seem to be
# immutable. that's a bummer but by setting this value to 7MiB we can
# work around it. why 7? the partition offset is already at 1MiB so
# adding 7MiB brings it to 8MiB. also, note that the locked data is
# mostly zeroes and thankfully the area under the clear zone is
# completely zeroes so it reads back "correctly" as zeroes.
COMMON_CACHE_PARTITION_CLEAR_ZONE="$(( (7*(1024**2)) ))"

# the "reserved area" is where the stage data is saved for offline
# booting.
CLASSICAL_LANDER_RESERVED_AREA_SIZE="$(( (128*(1024**2)) ))"
CLASSICAL_LANDER_RESERVED_AREA_ALIGN="$((  (1*(1024**2)) ))"
