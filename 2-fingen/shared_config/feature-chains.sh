CHAIN_SEPARATOR=ymHX6T5FLqBsRg1f

CHAIN_OVERLAYS=("$CHAIN_SEPARATOR")
CHAIN_ACT_ROOT=("$CHAIN_SEPARATOR")
CHAIN_ACT_USER=("$CHAIN_SEPARATOR")

function chain_inner_append()
{
  CC+=("$@" "$CHAIN_SEPARATOR")
}

function chain_inner_remove_match()
{
  local MP
  MP=("$@")
  
  local MPn
  MPn="${#MP[@]}"
  
  local CCn
  CCn="${#CC[@]}"
  
  if (( (CCn-i-1)<MPn ))
  then
    return 1
  fi
  
  local ii
  for ((ii=0; ii<MPn; ii++))
  do
    local iii
    iii=$(( (i+ii) ))
    local CCiii
    CCiii="${CC[$iii]}"
    
    echo "CCiii='$CCiii'"
    if [ "${MP[$ii]}" != "$CCiii" ]
    then
      return 1
    fi
  done
  
  return 0
}

function chain_inner_remove()
{
  local PS # previous was separator
  PS=y
  
  local n
  n="${#CC[@]}"
  local i
  for ((i=0; i<n; i++))
  do
    local CCi
    CCi="${CC[$i]}"
    
    declare -p CC
    chain_inner_remove_match "$@" || true
    declare -p CC
    
    if [ "$PS" == "y" ] && chain_inner_remove_match "$@"
    then
      echo "!!! MATCH !!!"
      CC[$i]=_
    fi
    
    if [ "$CCi" == "$CHAIN_SEPARATOR" ]
    then
      PS=y
    else
      PS=n
    fi
  done
}

function chain_inner_runall()
{
  local CT
  CT=(_)
  
  local i
  for i in "${CC[@]}"
  do
    if [ "$i" == "$CHAIN_SEPARATOR" ]
    then
      if (( "${#CT[@]}" > 1 ))
      then
        #declare -p CT
        
        if [ "${CT[1]}" != "_" ]
        then
          local CMD
          CMD=("${CT[@]:1}")
          echo -n "  "
          declare -p CMD
          echo '  "${CMD[@]}"'
        fi
      fi
      
      CT=(_)
    else
      CT+=("$i")
    fi
  done
}

function chain_overlays_append()
{
  local CC
  CC=("${CHAIN_OVERLAYS[@]}")
  chain_inner_append "$@"
  CHAIN_OVERLAYS=("${CC[@]}")
}

function chain_overlays_remove()
{
  local CC
  CC=("${CHAIN_OVERLAYS[@]}")
  chain_inner_remove "$@"
  CHAIN_OVERLAYS=("${CC[@]}")
}

function chain_act_root_append()
{
  local CC
  CC=("${CHAIN_ACT_ROOT[@]}")
  chain_inner_append "$@"
  CHAIN_ACT_ROOT=("${CC[@]}")
}

function chain_act_root_remove()
{
  local CC
  CC=("${CHAIN_ACT_ROOT[@]}")
  chain_inner_remove "$@"
  CHAIN_ACT_ROOT=("${CC[@]}")
}

function chain_act_user_append()
{
  local CC
  CC=("${CHAIN_ACT_USER[@]}")
  chain_inner_append "$@"
  CHAIN_ACT_USER=("${CC[@]}")
}

function chain_act_user_remove()
{
  local CC
  CC=("${CHAIN_ACT_USER[@]}")
  chain_inner_remove "$@"
  CHAIN_ACT_USER=("${CC[@]}")
}

function chain_act_root_runall()
{
  local CC
  CC=("${CHAIN_ACT_ROOT[@]}")
  chain_inner_runall
}

function chain_act_user_runall()
{
  local CC
  CC=("${CHAIN_ACT_USER[@]}")
  chain_inner_runall
}

if false # if true, run some tests
then
  #set -o xtrace
  function ins_chains()
  {
    declare -p CHAIN_{OVERLAYS,ACT_{ROOT,USER}}
  }
  ins_chains
  chain_overlays_append poppy
  ins_chains
  chain_overlays_remove poppy
  ins_chains
  chain_act_root_append echo hi "it's me" mario
  ins_chains
  chain_act_root_append echo halogen "it's me" mario
  ins_chains
  chain_act_root_append true echo
  ins_chains
  chain_act_root_remove echo ho
  ins_chains
  #chain_act_root_remove echo halogen "it's me" mario
  chain_act_root_remove echo halogen
  ins_chains
  chain_act_root_append echo hi "it's me" mario
  ins_chains
  chain_act_root_runall
fi
