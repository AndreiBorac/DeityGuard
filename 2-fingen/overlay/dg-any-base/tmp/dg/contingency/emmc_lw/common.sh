#!/bin/false

function accurate_nt_()
{
  local a
  local b
  
  a="$1"
  b="$2"
  
  [ -e "$a" ]
  
  if [ ! -e "$b" ]
  then
    accurate_nt_result=y
    return
  fi
  
  a="$(readlink -f "$a")"
  b="$(readlink -f "$b")"
  
  a="$(find "$a" -printf "%T@")"
  b="$(find "$b" -printf "%T@")"
  
  if [ string_"$a" > string_"$b" ]
  then
    accurate_nt_result=y
  else
    accurate_nt_result=n
  fi
}

function check_is_mmcblk0()
{
  is_mmcblk0=n
  
  if [ ! -b /dev/mmcblk0 ] || [ ! -b "$1" ]
  then
    return 0
  fi
  
  local {final,majmi}_{ref,arg}
  
  final_ref="$(readlink -f /dev/mmcblk0)"
  final_arg="$(readlink -f "$1")"
  
  majmi_ref="$(stat -c %t:%T "$final_ref")"
  majmi_arg="$(stat -c %t:%T "$final_arg")"
  
  if [ "$majmi_arg" == "$majmi_ref" ]
  then
    is_mmcblk0=y
  fi
}

function check_wr_mmcblk0()
{
  if [ ! -w /dev/mmcblk0 ]
  then
    set +o xtrace
    echo "!! giving up since no write permission for /dev/mmcblk0"
    echo "!! bye"
    exit 1
  fi
}

function dd_()
{
  local WHICH_DD
  WHICH_DD="$(which dd)"
  "$WHICH_DD" "$@" oflag=seek_bytes iflag=fullblock,skip_bytes,count_bytes bs=16M conv=notrunc,fdatasync status=progress 2>/dev/null
}

function get_drive_size()
{
  local DUT
  DUT="$1"
  
  if [ -f "$DUT" ]
  then
    stat -c %s "$(readlink -f "$DUT")"
  else
    blockdev --getsize64 "$DUT"
  fi
}

function gpt_model_transplant_src_dst()
{
  local SRC
  SRC="$1"
  local DST
  DST="$2"
  
  local SZ_SRC
  SZ_SRC="$(get_drive_size "$SRC")"
  local SZ_DST
  SZ_DST="$(get_drive_size "$DST")"
  [ "$SZ_SRC" == "$SZ_DST" ]
  
  local SIZE_MODEL_HEAD
  SIZE_MODEL_HEAD="$(( (34*512) ))"
  dd_ if="$SRC" of="$DST" count="$SIZE_MODEL_HEAD"
  
  local SIZE_MODEL_TAIL
  SIZE_MODEL_TAIL="$(( (33*512) ))"
  dd_ if="$SRC" of="$DST" skip="$(( (SZ_SRC-SIZE_MODEL_TAIL) ))" seek="$(( (SZ_DST-SIZE_MODEL_TAIL) ))" count="$SIZE_MODEL_TAIL"
}

function gpt_model_rd()
{
  tmp_model="$(mktemp)"
  tmp_model_paa="$(mktemp)"
  tmp_model_gpt="$(mktemp)"
  tmp_model_bou="$(mktemp)"
  tmp_model_bup="$(mktemp)"
  tmp_model_trk="$(mktemp)"
  
  local DUT
  DUT="$1"
  
  local SIZE
  SIZE="$(get_drive_size "$DUT")"
  truncate -s "$SIZE" "$tmp_model"
  
  gpt_model_transplant_src_dst "$DUT" "$tmp_model"
  
  #if [ "$DUT" == "/dev/mmcblk0" ] && [ "$CLASSICAL_LANDER_EMMC_LOCKED_WORKAROUND" == "y" ]
  #then
    local SIZE_MODEL_HEAD
    SIZE_MODEL_HEAD="$(( (34*512) ))"
    local SIZE_MODEL_TAIL
    SIZE_MODEL_TAIL="$(( (33*512) ))"
    dd_ if="$tmp_model" of="$tmp_model_paa" skip="$(( (SIZE-SIZE_MODEL_TAIL) ))" count="$(( (SIZE_MODEL_TAIL-512) ))"
    [ "$(stat -c %s "$tmp_model_paa")" == $(( (32*512) )) ]
    dd_ if="$tmp_model" of="$tmp_model_gpt" skip="$(( (SIZE-512) ))" count=512
    [ "$(stat -c %s "$tmp_model_gpt")" == 512 ]
    cat "$tmp_model_gpt" "$tmp_model_paa" >"$tmp_model_bou"
    # gptize need not always succeed, of course. the secondary GPT may
    # be corrupt or the disk may simply not be GPT at all.
    if /tmp/dg/initramfs/gptize "$SIZE" <"$tmp_model_bou" >"$tmp_model_bup"
    then
      local SZ_BUP
      SZ_BUP="$(stat -c %s "$tmp_model_bup")"
      [ "$SZ_BUP" == "$SIZE_MODEL_HEAD" ]
      dd_ if="$tmp_model_bup" of="$tmp_model"
    fi
  #fi
  
  touch "$tmp_model_trk"
}

function gpt_model_wb()
{
  local DUT
  DUT="$1"
  
  if [ "$DUT" != "/dev/null" ]
  then
    gpt_model_transplant_src_dst "$tmp_model" "$DUT"
  fi
  
  rm -f "$tmp_model" "$tmp_model_paa" "$tmp_model_gpt" "$tmp_model_bou" "$tmp_model_bup" "$tmp_model_trk"
}
