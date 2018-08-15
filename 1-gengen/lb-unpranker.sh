#!/bin/false

. /builds/elvopt

TOOL=unpranker

function verify()
{
  local AC
  AC="$(sha256sum "$1" | cut -d " " -f 1)"
  [ "$AC" == "$2" ]
}

for ARMVER in x64 "${ARMVERS[@]:1}"
do
  (
    rm -rf --one-file-system /builds/"$TOOL"-"$ARMVER"
    mkdir -p                 /builds/"$TOOL"-"$ARMVER"
    cd                       /builds/"$TOOL"-"$ARMVER"
    
    FL="$TOOL".c
    
    . /tmp/libaboon/builder.sh
    
    ln -vsf -t ./ ./../../../tmp/{libaboon,"$FL"}
    
    verify  /sources/special_for_unpranker_xz-embedded-"$OPTION_VERSION_XZ_EMBEDDED".tar.gz "$OPTION_VERSION_XZ_EMBEDDED_SHA"
    tar -xf /sources/special_for_unpranker_xz-embedded-"$OPTION_VERSION_XZ_EMBEDDED".tar.gz
    
    mkdir ./xz-embedded
    ln -vsf -t ./xz-embedded/ ./../xz-embedded-"$OPTION_VERSION_XZ_EMBEDDED"/{userspace/xz_config.h,linux/{include/linux/xz.h,lib/xz/xz_{{crc32,dec_bcj,dec_lzma2,dec_stream}.c,{lzma2,private,stream}.h}}}
    ls -alh ./xz-embedded/
    
    OPTS=(-DIGNORE_THIS_MTN44dssxY3Inu2B)
    
    if [ "$FLAG_LIGHTSOUT" == "y" ]
    then
      OPTS+=(-DLB_SPACE_OPTIMIZED)
    else
      cat >./cond.c <<'EOF'
#define LB_TRACE_COND (LB_CURRENT_FILE == 0)
EOF
    fi
    
    OPTS+=(-Os)
    OPTS+=(-fomit-frame-pointer)
    OPTS+=(-Wl,--build-id=none)
    
    if [ "$ARMVER" == "x64" ]
    then
      echo >./tc-x64
      lb_tc_config x64
    else
      . /tmp/common-cross-compile.sh
      cross_compile_setup "$ARMVER"
      echo /tmp/cross_compile- >./tc-arm
      lb_tc_config arm
      export LB_CROSS_EXEC="qemu-arm -cpu cortex-a15"
      OPTS+=(-marm) # libaboon can't handle thumb mode at this time
    fi
    
    lb_prepare_lbt
    lb_gcc "$(basename "$FL" .c)" "$FL" "${OPTS[@]}"
    lb_strip "$(basename "$FL" .c)"
    
    wc -c <./unpranker
    "$LB_TOOLCHAIN_PREFIX"readelf -e ./unpranker >./unpranker.readelf.txt
    cp ./unpranker.readelf.txt ./../
    
    cp --reflink=auto ./"$(basename "$FL" .c)" ./../
  )
done
