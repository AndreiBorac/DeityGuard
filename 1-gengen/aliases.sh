#!/bin/false

if [ -z "${BASH_VERSION-}" ]
then
  echo "!! THESE MACROS ARE ONLY DESIGNED TO WORK IN BASH"
  echo "!! PLEASE USE BASH"
  echo "!! BYE"
  return
fi

function ___gengen_aliases_maint_brarm_xconfig()        { ___gengen_prefix --maint-brarm-xconfig-helper ./maint-brarm.sh xconfig ;}
function ___gengen_aliases_maint_brarm()                { ___gengen_prefix --maint-brarm-helper         ./maint-brarm.sh         ;}

function ___gengen_aliases_gengen_dl()                  { ___gengen_prefix ./gengen.sh ;}
function ___gengen_aliases_gengen_ex()                  { ___gengen_prefix ./gengen.sh "$@" ;}
function ___gengen_aliases_gengen_gentoo_stage3()       { ___gengen_prefix ./gengen.sh stage3  backtrack squashfs unikitmaybe "$@" ;}
function ___gengen_aliases_gengen_gentoo_portage()      { ___gengen_prefix ./gengen.sh portage backtrack squashfs unikitmaybe "$@" ;}
function ___gengen_aliases_gengen_gentoo_world()        { ___gengen_prefix ./gengen.sh world   backtrack squashfs unikitmaybe "$@" ;}
function ___gengen_aliases_gengen_gentoo_world_dryrun() { ___gengen_prefix ./gengen.sh world   backtrack dryrun "$@" ;}
function ___gengen_aliases_gengen_brarm()               { ___gengen_prefix ./gengen.sh ca7 ca17 brarm brarm-{purge,everything} "$@" unikitmaybe ;}
function ___gengen_aliases_gengen_brarm_dirclean()      { ___gengen_prefix bash -c './gengen.sh && ./gengen.sh brarm-dirclean "$@"' -- "$@" ;}
function ___gengen_aliases_gengen_linux()               { ___gengen_prefix ./gengen.sh linux "$@" unikitmaybe ;}
function ___gengen_aliases_gengen_linux_min()           { ___gengen_prefix ./gengen.sh linux-min "$@" unikitmaybe ;}
function ___gengen_aliases_gengen_arm_linux_bpi()       { ___gengen_prefix ./gengen.sh ca7  arm-linux-bpi "$@" unikitmaybe ;}
function ___gengen_aliases_gengen_arm_linux_rok()       { ___gengen_prefix ./gengen.sh ca17 arm-linux-rok "$@" unikitmaybe ;}
function ___gengen_aliases_gengen_coreboot()            { ___gengen_prefix ./gengen.sh coreboot unikitmaybe ;}
function ___gengen_aliases_gengen_arm_u_boot()          { ___gengen_prefix ./gengen.sh ca7 arm-u-boot unikitmaybe ;}
function ___gengen_aliases_gengen_tools()               { ___gengen_prefix ./gengen.sh ca7 ca17 nbd-hyperbolic unpranker lightsout && ___gengen_prefix ./gengen.sh ca7 ca17 instigator safepipe murmur linuxtools fanman gptize flashpagan unikitmaybe ;}
function ___gengen_aliases_gengen_flashpagan()          { ___gengen_prefix ./gengen.sh flashpagan unikitmaybe ;}
function ___gengen_aliases_gengen_unikit()              { ___gengen_prefix ./gengen.sh unikit ;}

function ___gengen_prefix_locally()
{
  [ "$1" == "--maint-brarm-xconfig-helper" ] && shift
  [ "$1" == "--maint-brarm-helper"         ] && shift
  
  "$@"
}

function ___gengen_prefix_boomerang()
{
  if [ "${GENGEN_NETESC+set}" == "set" ]
  then
    $GENGEN_ALIASES_BOOMERANG_NETESC env GENGEN_NETESC="${GENGEN_NETESC-}" ./boomerang.sh "$@"
  else
    $GENGEN_ALIASES_BOOMERANG_NETESC                                       ./boomerang.sh "$@"
  fi
}

for ___gengen_aliases_i in locally boomerang
do
  for ___gengen_aliases_j in maint_brarm_xconfig maint_brarm gengen_{dl,ex,gentoo_{stage3,portage,world{,_dryrun}},brarm{,_dirclean},linux{,_min},arm_linux_{bpi,rok},coreboot,arm_u_boot,tools,flashpagan,unikit}
  do
    eval "function dg_${___gengen_aliases_i}_${___gengen_aliases_j}() { function ___gengen_prefix() { ___gengen_prefix_${___gengen_aliases_i} \"\$@\" ;}; ___gengen_aliases_${___gengen_aliases_j} \"\$@\" ;}"
  done
done

function dg_setup_reload()
(
  set -o xtrace
  set -o errexit
  set -o nounset
  set -o pipefail
  
  tar -xf ./../../../ithird/deityguard.tar.xz     --strip-components=2 deityguard/1-gengen/
  tar -xf ./../../../ithird/overlay.tar.gz        --strip-components=2          ./1-gengen/ || true
  
  if [ "${1-}" == "both" ]
  then
    (
      cd ./../2-fingen
      
      tar -xf ./../../../ithird/deityguard.tar.xz --strip-components=2 deityguard/2-fingen/
      tar -xf ./../../../ithird/overlay.tar.gz    --strip-components=2          ./2-fingen/ || true
    )
  fi
  
  set +o xtrace
  echo "note: errors from unpacking overlay.tar.gz are normal under some circumstances"
)
