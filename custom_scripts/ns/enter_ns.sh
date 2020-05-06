#!/bin/bash -eu
# enter_ns.sh
# 
# execute a command inside an ns
# provide the pid of the pid=1 process in the ns
# you want to join.
# 

# we'll need a pid for sure.
if [[ -z ${SUDO_USER+x} && -z ${1+x} ]]; then
  echo "Usage: $0 <ppid in ns> <command and args>" 1>&2
  exit 1
fi

# we'll need just a numeric uid
if [[ ! ( "$1" =~ ^[0-9]+$ )]]; then
  echo "ppid does not look like a pid" 1>&2
  exit 1
fi

ppid=$1
shift

# get uid/gid of process so we know what to feed to sudo.
if [[ -z ${SUDO_USER+x} ]]; then

  puid=$( ps -o uid --no-headers -p $ppid | sed -e 's/ //' )
  pgid=$( ps -o gid --no-headers -p $ppid | sed -e 's/ //' )

  # test 1: uid and gid should be numeric
  if [[ ! ( "$puid" =~ ^[0-9]+$ ) || ! ( "$pgid" =~ ^[0-9]+$ ) ]]; then
    echo "UID/GID of ppid wasn't a number. What?!" 1>&2
    exit 1
  fi
  
  # test 2: ns was initialized as uid = gid, should still be that way
  if [[ $puid -ne $pgid ]]; then
    echo "Ppid UID should match GID. It does not. $puid $pgid" 1>&2
    exit 1
  fi

  # test 3: puids were chosen out of an unallocated UID range.
  # the puid should not map to an account.
  pwent=$( getent passwd $puid || true )
  grent=$( getent group $pgid || true )
  if [[ ! ( -z "$pwent" ) || ! ( -z "$grent" ) ]]; then
    echo "Ppid UID or GID has passwd/group entry. They should be unassigned." 1>&2
    exit 1
  fi
  
  # guess we're good to go.
  exec sudo -g \#"$pgid" -u \#"$puid" $( cd $( dirname $0 ); pwd )/$( basename $0 ) $ppid "$@"
fi


# we can assume this only gets executed via sudo, since the above exec never returns
# control to this script.
/usr/local/bin/nent -m -p -U -G0 -S0 -r --wd=/ -t $ppid "$@"
