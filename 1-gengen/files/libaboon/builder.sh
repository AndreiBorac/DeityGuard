#!/usr/bin/env bash

set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
shopt -s failglob
shopt -s nullglob

[ -d ./build ] || sudo mkdir -m 0000 ./build
sudo mountpoint -q ./build && sudo umount ./build
sudo mountpoint -q ./build && exit 1
sudo mountpoint -q ./build || sudo mount -t tmpfs none ./build
cd ./build

function lb_prepare_lbt_inner_common()
{
  (
    set +o xtrace
    
    echo "#define _GNU_SOURCE"
    
    for i in inttypes.h stdio.h "${INCLUDES[@]}"
    do
      echo "#include <${i}>"
    done
    echo -n '
int main(void)
{
'
    for i in "${SYMBOLS[@]}"
    do
      echo "  printf(\"#define lbt_${i} %\" PRId64 \"\\n\", ((int64_t)(${i})));"
    done
    for i in "${STRUCTS[@]}"
    do
      NAME="$(echo "$i" | cut -d ":" -f 1)"
      TYPE="$(echo "$i" | cut -d ":" -f 2)"
      echo "  printf(\"#define lbt_sizeof_${NAME} %\" PRId64 \"\\n\", ((int64_t)(sizeof(*((${TYPE}*)(NULL))))));"
    done
    for i in "${MEMBERS[@]}"
    do
      ISTRUCT="$(echo "$i" | cut -d ":" -f 1)"
      OSTRUCT="$(echo "$i" | cut -d ":" -f 2)"
      IMEMBER="$(echo "$i" | cut -d ":" -f 3)"
      OMEMBER="$(echo "$i" | cut -d ":" -f 4)"
      echo "  printf(\"#define lbt_sizeof_${ISTRUCT}_${IMEMBER} %\" PRId64 \"\\n\", ((int64_t)(sizeof(((${OSTRUCT}*)(NULL))->${OMEMBER}))));"
      echo "  printf(\"#define lbt_offsetof_${ISTRUCT}_${IMEMBER} %\" PRId64 \"\\n\", ((int64_t)(__builtin_offsetof(${OSTRUCT}, ${OMEMBER}))));"
    done
    echo -n '
  return 0;
}
'
  ) >./lbt.c
  "$LB_TOOLCHAIN_PREFIX""$LB_COMPILER" -o ./lbt.{x,c} -static
  ${LB_CROSS_EXEC-} ./lbt.x >./lbt.h
}

function lb_prepare_lbt_inner_ANY()
{
  INCLUDES=(unistd.h sysexits.h sys/syscall.h sys/types.h sys/stat.h fcntl.h signal.h sys/epoll.h errno.h sys/{socket,un}.h netinet/in.h arpa/inet.h sys/timerfd.h sys/eventfd.h linux/aio_abi.h sys/ioctl.h net/if.h linux/if_packet.h net/ethernet.h net/route.h sys/mount.h sys/mman.h sys/wait.h)
  SYMBOLS=(
    SYS_{statfs,setns,ftruncate,sendfile,rt_sigpending,getuid,get_mempolicy,sched_get_priority_min,io_submit,reboot,getsockopt,request_key,rt_sigreturn,inotify_rm_watch,sched_setaffinity,msgctl,sync,flock,tkill,munmap,clock_getres,mremap,inotify_init,removexattr,chroot,preadv,pwrite64,msgrcv,mq_timedreceive,setuid,readlink,setresgid,fanotify_init,pause,vmsplice,semop,signalfd4,openat,shmat,open,getcpu,inotify_init1,fchdir,shmdt,setpgid,utimes,getcwd,process_vm_readv,epoll_pwait,lgetxattr,read,accept,kcmp,clock_adjtime,geteuid,flistxattr,link,getresgid,access,setitimer,getgid,mkdir,clock_nanosleep,fchown,execve,vfork,splice,dup,poll,rt_sigaction,prctl,timer_delete,lookup_dcookie,fgetxattr,getitimer,epoll_create1,getpgid,timerfd_gettime,getpgrp,futimesat,linkat,recvfrom,mount,wait4,keyctl,mlockall,fstatfs,clone,getpriority,kexec_load,getegid,llistxattr,fsync,close,quotactl,getrusage,clock_settime,chmod,setgid,_sysctl,getsockname,set_robust_list,mbind,setfsuid,write,setsockopt,lseek,sched_setattr,sched_getaffinity,setxattr,add_key,writev,timerfd_settime,adjtimex,msgsnd,rt_tgsigqueueinfo,name_to_handle_at,epoll_wait,symlinkat,times,connect,rt_sigqueueinfo,mkdirat,sendto,fchownat,utimensat,recvmmsg,eventfd2,swapoff,set_mempolicy,set_tid_address,ioprio_get,clock_gettime,getsid,readahead,lstat,rename,io_cancel,setreuid,unlink,fsetxattr,sched_getattr,setgroups,pipe2,uselib,sched_setscheduler,sched_yield,tee,setfsgid,mlock,umask,epoll_ctl,rmdir,perf_event_open,acct,sysinfo,sched_setparam,inotify_add_watch,listen,timerfd_create,restart_syscall,ptrace,shmctl,setresuid,renameat2,signalfd,getgroups,nfsservctl,io_destroy,unshare,bind,getxattr,pwritev,dup2,dup3,pipe,timer_create,mincore,settimeofday,fallocate,shmget,fchmod,vhangup,socket,stat,pread64,faccessat,syncfs,fcntl,setsid,exit_group,sched_getscheduler,tgkill,sendmmsg,futex,capget,listxattr,getpid,brk,setrlimit,setregid,waitid,creat,userfaultfd,personality,semtimedop,fork,ioctl,getpeername,madvise,recvmsg,pivot_root,gettimeofday,socketpair,getppid,remap_file_pages,symlink,swapon,fdatasync,rt_sigtimedwait,get_robust_list,gettid,open_by_handle_at,msgget,sched_getparam,ioprio_set,memfd_create,exit,process_vm_writev,sigaltstack,lchown,renameat,ppoll,nanosleep,semctl,timer_settime,kill,fanotify_mark,timer_getoverrun,ustat,finit_module,epoll_create,msync,readlinkat,semget,getdents,mq_getsetattr,readv,mq_unlink,sysfs,delete_module,mknodat,chdir,eventfd,rt_sigsuspend,unlinkat,vserver,setdomainname,uname,getrandom,prlimit64,io_setup,lremovexattr,fstat,sethostname,truncate,syslog,timer_gettime,io_getevents,munlock,mq_notify,chown,init_module,munlockall,capset,move_pages,accept4,mprotect,mknod,lsetxattr,fremovexattr,sendmsg,shutdown,setpriority,rt_sigprocmask,sched_rr_get_interval,fchmodat,mq_open,getdents64,pselect6,umount2,mq_timedsend,getresuid,sched_get_priority_max}
    # excluded due to not being available on Centos 7 OVH (4.9.33-mod-std-ipv6-64):
    # mlock2,membarrier,bpf,execveat,seccomp
    O_{CREAT,TRUNC,RDONLY,WRONLY,RDWR,NONBLOCK}
    EX_SOFTWARE
    SIG{HUP,INT,QUIT,ILL,TRAP,ABRT,BUS,FPE,KILL,USR1,SEGV,USR2,PIPE,ALRM,TERM,STKFLT,CHLD,CONT,STOP,TSTP,TTIN,TTOU,URG,XCPU,XFSZ,VTALRM,PROF,WINCH,IO,PWR,SYS,RTMIN,RTMAX}
    SIG_{,UN}BLOCK
    EPOLL{IN,OUT}
    EPOLL_CTL_{ADD,DEL}
    F_{GET,SET}FL
    E{DEADLK,NAMETOOLONG,NOLCK,NOSYS,NOTEMPTY,LOOP,WOULDBLOCK,NOMSG,IDRM,CHRNG,L2NSYNC,L3HLT,L3RST,LNRNG,UNATCH,NOCSI,L2HLT,BADE,BADR,XFULL,NOANO,BADRQC,BADSLT,DEADLOCK,BFONT,NOSTR,NODATA,TIME,NOSR,NONET,NOPKG,REMOTE,NOLINK,ADV,SRMNT,COMM,PROTO,MULTIHOP,DOTDOT,BADMSG,OVERFLOW,NOTUNIQ,BADFD,REMCHG,LIBACC,LIBBAD,LIBSCN,LIBMAX,LIBEXEC,ILSEQ,RESTART,STRPIPE,USERS,NOTSOCK,DESTADDRREQ,MSGSIZE,PROTOTYPE,NOPROTOOPT,PROTONOSUPPORT,SOCKTNOSUPPORT,OPNOTSUPP,PFNOSUPPORT,AFNOSUPPORT,ADDRINUSE,ADDRNOTAVAIL,NETDOWN,NETUNREACH,NETRESET,CONNABORTED,CONNRESET,NOBUFS,ISCONN,NOTCONN,SHUTDOWN,TOOMANYREFS,TIMEDOUT,CONNREFUSED,HOSTDOWN,HOSTUNREACH,ALREADY,INPROGRESS,STALE,UCLEAN,NOTNAM,NAVAIL,ISNAM,REMOTEIO,DQUOT,NOMEDIUM,MEDIUMTYPE,CANCELED,NOKEY,KEYEXPIRED,KEYREVOKED,KEYREJECTED,OWNERDEAD,NOTRECOVERABLE,RFKILL,HWPOISON}
    E{AGAIN,EXIST}
    AF_{UNIX,INET,PACKET} PF_{INET,PACKET} IPPROTO_{RAW,IP} ETH_P_IP
    SOCK_{RAW,DGRAM,STREAM}
    SOL_SOCKET
    SO_REUSEADDR
    CLOCK_{REALTIME,MONOTONIC} TFD_{NONBLOCK,CLOEXEC} EFD_{NONBLOCK,CLOEXEC,SEMAPHORE}
    IOCB_{CMD_P{READ,WRITE},CMD_F{,D}SYNC,FLAG_RESFD}
    IFNAMSIZ
    SIOCGIF{INDEX,HWADDR}
    SIOC{G,S}IF{FLAGS,ADDR,NETMASK} IFF_{UP,BROADCAST,RUNNING,MULTICAST}
    SIOCADDRT RTF_{UP,GATEWAY}
    MS_SILENT
    MCL_{CURRENT,FUTURE}
    SEEK_{SET,CUR,END}
    W{NOHANG,UNTRACED,CONTINUED}
  )
  STRUCTS=(
    stat:struct" "stat
    sockaddr_un:struct" "sockaddr_un
    sockaddr_in:struct" "sockaddr_in
    sockaddr_ll:struct" "sockaddr_ll
    epoll_event:struct" "epoll_event
    timespec:struct" "timespec
    itimerspec:struct" "itimerspec
    iocb:struct" "iocb
    io_event:struct" "io_event
  )
  MEMBERS=(
    sockaddr_un:struct" "sockaddr_un:sun_family:sun_family
    sockaddr_un:struct" "sockaddr_un:sun_path:sun_path
    sockaddr_in:struct" "sockaddr_in:sin_family:sin_family
    sockaddr_in:struct" "sockaddr_in:sin_port:sin_port
    sockaddr_in:struct" "sockaddr_in:sin_addr_s_addr:sin_addr.s_addr
    sockaddr_ll:struct" "sockaddr_ll:sll_family:sll_family
    sockaddr_ll:struct" "sockaddr_ll:sll_protocol:sll_protocol
    sockaddr_ll:struct" "sockaddr_ll:sll_ifindex:sll_ifindex
    sockaddr_ll:struct" "sockaddr_ll:sll_hatype:sll_hatype
    sockaddr_ll:struct" "sockaddr_ll:sll_pkttype:sll_pkttype
    sockaddr_ll:struct" "sockaddr_ll:sll_halen:sll_halen
    sockaddr_ll:struct" "sockaddr_ll:sll_addr:sll_addr
    epoll_event:struct" "epoll_event:events:events
    epoll_event:struct" "epoll_event:data_ptr:data.ptr
    timespec:struct" "timespec:tv_sec:tv_sec
    timespec:struct" "timespec:tv_nsec:tv_nsec
    itimerspec:struct" "itimerspec:it_interval:it_interval
    itimerspec:struct" "itimerspec:it_value:it_value
    iocb:struct" "iocb:aio_data:aio_data
    iocb:struct" "iocb:aio_key:aio_key
    iocb:struct" "iocb:aio_lio_opcode:aio_lio_opcode
    iocb:struct" "iocb:aio_reqprio:aio_reqprio
    iocb:struct" "iocb:aio_fildes:aio_fildes
    iocb:struct" "iocb:aio_buf:aio_buf
    iocb:struct" "iocb:aio_nbytes:aio_nbytes
    iocb:struct" "iocb:aio_offset:aio_offset
    iocb:struct" "iocb:aio_flags:aio_flags
    iocb:struct" "iocb:aio_resfd:aio_resfd
    io_event:struct" "io_event:data:data
    io_event:struct" "io_event:obj:obj
    io_event:struct" "io_event:res:res
    io_event:struct" "io_event:res2:res2
  )
}

function lb_prepare_lbt_inner_X86_64()
{
  lb_prepare_lbt_inner_ANY
  SYMBOLS+=(
    SYS_{time,security,newfstatat,modify_ldt,query_module,get_thread_area,utime,iopl,afs_syscall,get_kernel_syms,mmap,tuxcall,kexec_file_load,alarm,fadvise64,epoll_wait_old,ioperm,set_thread_area,getrlimit,migrate_pages,create_module,epoll_ctl_old,putpmsg,sync_file_range,select,getpmsg,arch_prctl}
  )
  lb_prepare_lbt_inner_common
}

function lb_prepare_lbt_inner_ARM_32()
{
  lb_prepare_lbt_inner_ANY
  SYMBOLS+=(
    SYS_set{u,g}id32
  )
  lb_prepare_lbt_inner_common
}

function lb_prepare_lbt()
{
  local SHA
  SHA="$(declare -f lb_prepare_lbt_inner_common lb_prepare_lbt_inner_ANY lb_prepare_lbt_inner_"$LB_ARCH" | sha256sum - | cut -d " " -f 1)"
  
  if [ -d ./../local ]
  then
    if [ ! -f ./../local/lbt-"$SHA".h ]
    then
      lb_prepare_lbt_inner_"$LB_ARCH"
      
      cp ./lbt.h ./../local/lbt-"$SHA".h
    fi
    
    cp ./../local/lbt-"$SHA".h ./lbt.h
  else
    lb_prepare_lbt_inner_"$LB_ARCH"
  fi
}

function lb_gcc()
{
  local OPT
  OPT="$(echo --std=c99 -fdiagnostics-color=always -W{error,all,extra,conversion,shadow,{strict,missing}-prototypes,c++-compat,missing-field-initializers,switch-default,inline} --all-warnings -Wno-unused-function)"
  local OPL
  OPL="$(echo -no{startfiles,stdlib,defaultlibs} -fno-pie -no-pie)"
  
  OPT="$OPT -DLB_ARCH_$LB_ARCH"
  
  (
    echo '#include "./lbt.h"'
    
    if [ -f ./cond.c ]
    then
      echo '#include "./cond.c"'
    fi
    
    echo '#include "./libaboon/everything.c"'
  ) >./libaboon-builder.h
  
  local OF
  OF="$1"
  shift
  local SF
  SF="$1"
  shift
  "$LB_TOOLCHAIN_PREFIX""$LB_COMPILER" $OPT "$@" -o ./"$OF" -x c ./"$SF" $OPL
}

function lb_strip()
{
  local OF
  OF="$1"
  ls -l ./"$OF"
  "$LB_TOOLCHAIN_PREFIX"strip ./"$OF"
  ls -l ./"$OF"
  local i
  for i in .note.gnu.build-id .eh_frame{,_hdr} .comment
  do
    "$LB_TOOLCHAIN_PREFIX"objcopy --remove-section "$i" ./"$OF"
    ls -l ./"$OF"
  done
}

function lb_minkey()
{
  local FL
  FL="$1"
  shift
  
  lb_gcc            minkey                 "$FL" -g "$@"
  
  local OPTS
  OPTS=""
  
  function lb_minkey_strip()
  {
    lb_strip "$@"
  }
  
  if [ "${LB_BUILDER_ALWAYS_G-}" == "y" ]
  then
    OPTS="-g -fno-inline"
    function lb_minkey_strip() { true; }
  fi
  
  if [ "${LB_BUILDER_DEBUG_ONLY-}" != "y" ]
  then
    lb_gcc          minkey-basic-optimized "$FL" -Os $OPTS "$@"
    lb_minkey_strip minkey-basic-optimized
    lb_gcc          minkey-speed-optimized "$FL" -O2 $OPTS "$@"
    lb_minkey_strip minkey-speed-optimized
    lb_gcc          minkey-space-optimized "$FL" -DLB_SPACE_OPTIMIZED -Os -fomit-frame-pointer $OPTS "$@"
    lb_minkey_strip minkey-space-optimized
  fi
}

function lb_tc_config()
{
  if [ "$1" == "x64" ]
  then
    LB_ARCH=X86_64
    LB_TOOLCHAIN_PREFIX="$(cat ./tc-x64 || cat ./../tc-x64 || cat ./../local/tc-x64)"
  fi
  
  if [ "$1" == "arm" ]
  then
    LB_ARCH=ARM_32
    LB_TOOLCHAIN_PREFIX="$(cat ./tc-arm || cat ./../tc-arm || cat ./../local/tc-arm)"
  fi
  
  LB_COMPILER=gcc
}
