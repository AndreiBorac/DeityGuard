MANAGE_SSH_HOST_KEY=y

#include feature-chains

function _() { chain_overlays_append "$@" ;}
_ dg-any-base
unset _

f_defs

function _() { chain_act_root_append "$@" ;}
_ do_setup
_ do_rootpass "$ROOTSHADOW"
_ do_sudoers
_ do_open_serial_shell
_ do_autologin
_ do_dhcpc eth0
_ do_firewall
_ do_firewall_netwild
_ do_timezone "$TZDATA_TZ"
_ do_ntpdate
_ do_sshd
_ do_sshd_pkey_root "$PKEY_ROOT"
_ do_portage_fix
_ do_configure_x
#_ do_bashrc
_ do_no_history_root
_ do_create_user
unset _

function _() { chain_act_user_append "$@" ;}
_ do_setup
_ do_sshd_pkey_user "$PKEY_USER"
#_ do_bashrc
_ do_no_history_user
_ do_no_xscreensaver
_ do_xbindkeys
# try each known xinitrc in increasing order of preference, so that
# the latest working one wins. these functions are supposed to give up
# without writing xinitrc if the required software is not installed
_ do_xinitrc_xterm_fullscreen
_ do_xinitrc_fluxbox
_ do_xinitrc_openbox_tint2
_ do_xinitrc_xfce4
unset _
