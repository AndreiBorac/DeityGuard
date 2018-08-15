#!/bin/false

. /builds/elvopt

for ARMVER in x64 "${ARMVERS[@]:1}"
do
  (
    rm -rf --one-file-system /builds/"$TOOL"-"$ARMVER"
    mkdir -p                 /builds/"$TOOL"-"$ARMVER"
    cd                       /builds/"$TOOL"-"$ARMVER"
    
    FL="$TOOL".c
    
    . /tmp/libaboon/builder.sh
    
    ln -vsf -t ./ ./../../../tmp/{libaboon,"$FL"}
    
    OPTS=(-DIGNORE_THIS_MTN44dssxY3Inu2B)
    
    if [ "$FLAG_LIGHTSOUT" == "y" ]
    then
      OPTS+=(-DLB_SPACE_OPTIMIZED)
    else
      cat >./cond.c <<'EOF'
#define LB_TRACE_COND (LB_CURRENT_FILE == 0)
EOF
    fi
    
    if [ "$ARMVER" == "x64" ]
    then
      echo >./tc-x64
      lb_tc_config x64
    else
      . /tmp/common-cross-compile.sh
      cross_compile_setup "$ARMVER"
      echo /tmp/cross_compile- >./tc-arm
      lb_tc_config arm
      export LB_CROSS_EXEC="qemu-arm"
      OPTS+=(-marm) # libaboon can't handle thumb mode properly at this time
    fi
    
    lb_prepare_lbt
    lb_gcc   "$(basename "$FL" .c)" "$FL" "${OPTS[@]}"
    lb_strip "$(basename "$FL" .c)"
    
    cp --reflink=auto ./"$(basename "$FL" .c)" ./../
  )
done
