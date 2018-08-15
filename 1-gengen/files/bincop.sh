#!/bin/false

# BINCOP_DEST - output directory
# BINCOP_ROOT - root directory
# BINCOP_PATH - an array of program search directories, relative to the root directory
# BINCOP_LD_LIBRARY_PATH - an array of library search directories, relative to the root directory
# BINCOP_ZERO_POINT - stuff to be added by bincop_add_zero_point
# BINCOP_TOOLCHAIN_PREFIX - toolchain prefix for running objdump

function bincop_reset()
{
  BINCOP_DEST=()
  BINCOP_ROOT=()
  BINCOP_PATH=()
  BINCOP_LD_LIBRARY_PATH=()
  BINCOP_CURRENT_BINARY=()
  BINCOP_TOOLCHAIN_PREFIX=()
}

function bincop_clean_duplicates()
{
  cat "$1" | sort | uniq >"$1".tmp
  mv "$1"{.tmp,}
}

function bincop_locate()
{
  local NAME
  NAME="$1"
  shift
  
  [ -n "$NAME" ]
  
  if [ "${NAME:0:1}" == "/" ]
  then
    [ -f "$BINCOP_ROOT""$NAME" ]
    echo "${NAME:1}"
  else
    local BN_NAME
    BN_NAME="$(basename "$NAME")"
    [ "$BN_NAME" == "$NAME" ]
    
    local i
    for i in "$@"
    do
      if [ -f "$BINCOP_ROOT"/"$i"/"$NAME" ]
      then
        echo "$i"/"$NAME"
        return 0
      fi
    done
    
    set +o xtrace
    echo "bincop_locate: not found: '$NAME'"
    exit 1
  fi
}

function bincop_add_file_rr()
{
  local RR
  RR="$1"
  
  ( BINCOP_DEST_ABSOLUTE="$(readlink -f "$BINCOP_DEST")" ; cd "$BINCOP_ROOT"/ ; cp -vax --parents "$RR" "$BINCOP_DEST_ABSOLUTE"/ )
}

function bincop_add_binary_rr()
{
  local RR
  RR="$1"
  
  local BN
  BN="$(basename "$RR")"
  
  if [ ! -e "$BINCOP_DEST"/"$RR" ]
  then
    bincop_add_file_rr "$RR"
    echo "$RR" >"$BINCOP_DEST"/which_"$BN"
    echo "$RR" >"$BINCOP_DEST"/files_"$BN"
    
    if [ -h "$BINCOP_ROOT"/"$RR" ]
    then
      # it's a symlink
      local RL
      RL="$(readlink "$BINCOP_ROOT"/"$RR")"
      # locate it
      local FL
      local BN
      BN_RL="$(basename "$RL")"
      if [ "$BN_RL" == "$RL" ]
      then
        # symlink is just a basename
        local DN
        DN="$(dirname "$RR")"
        FL="$DN"/"$BN_RL"
      elif [ "${RL:0:1}" == "/" ]
      then
        # symlink is absolute
        FL="${RL:1}"
      else
        # the tough case ... but do we need this?
        set +o xtrace
        echo "!! sorry, I'm too dumb to handle relative symlinks"
        exit 1
      fi
      # chain
      bincop_add_binary_rr "$FL"
      cat "$BINCOP_DEST"/files_"$BN_RL" >>"$BINCOP_DEST"/files_"$BN"
    else
      if [ "$(hexdump -v -e \"%02x\" -n 2 "$BINCOP_ROOT"/"$RR")" == "2123" ]
      then
        # it's a shebang (#!) script. just copy it. we don't try to
        # recurse into copying the interpreting binary or
        # anything. actually we already copied it so we're done.
        true
      else
        # it's a real binary (or so we hope)
        "$BINCOP_TOOLCHAIN_PREFIX"readelf -a "$BINCOP_ROOT"/"$RR" >"$BINCOP_DEST"/readelfa_"$BN" # for debugging
        "$BINCOP_TOOLCHAIN_PREFIX"objdump -p "$BINCOP_ROOT"/"$RR" | ( egrep '^  NEEDED' || true ) |\
          (
            while read NN FN
            do
              (
                [ "$NN" == "NEEDED" ]
                # make sure the needed object is a bare basename
                BN_FN="$(basename "$FN")"
                [ "$BN_FN" == "$FN" ]
                # locate it
                FL="$(bincop_locate "$FN" "${BINCOP_LD_LIBRARY_PATH[@]}")"
                # chain
                bincop_add_binary_rr "$FL"
                cat "$BINCOP_DEST"/files_"$BN_FN" >>"$BINCOP_DEST"/files_"$BN"
              ) </dev/null
            done
          )
      fi
    fi
    
    bincop_clean_duplicates "$BINCOP_DEST"/files_"$BN"
  fi
}

function bincop_add_zero_point()
{
  if [ ! -f "$BINCOP_DEST"/files_zero_point ]
  then
    touch "$BINCOP_DEST"/files_zero_point
    
    local i
    for i in "${BINCOP_ZERO_POINT[@]}"
    do
      if [ "$i" != "" ]
      then
        local BN_I
        BN_I="$(basename "$i")"
        # chain
        bincop_add_binary_rr "$i"
        cat "$BINCOP_DEST"/files_"$BN_I" >>"$BINCOP_DEST"/files_zero_point
      fi
    done
    
    bincop_clean_duplicates "$BINCOP_DEST"/files_zero_point
  fi
}

function bincop_add_binary()
{
  local PROG
  PROG="$1"
  
  PROG="$(bincop_locate "$PROG" "${BINCOP_PATH[@]}")"
  bincop_add_binary_rr "$PROG"
}

function bincop_add_binaries()
{
  local i
  for i in "$@"
  do
    bincop_add_binary "$i"
  done
}
