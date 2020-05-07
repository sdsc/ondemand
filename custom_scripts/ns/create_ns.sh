#!/bin/bash
#
# create_ns.sh
# create a namespace and spin-lock in it until
# some important files appear.
#
# call this script as the uid you want to
# run the ns as. this probably means you need
# sudo -u \#NNNNN where NNNN is the numeric uid.
#
# returns PID of the pid 1 inside the new namespace.
#

# need a new root directory.
# except when in the new namespace.
if [[ "$1" == '' && $$ -ne 1 ]]; then
  echo "Usage: $0 <chroot directory>" 1>&2
  exit 1
fi

# where's this script running?
SCRIPTDIR=$( cd $(dirname $0) && pwd )
SCRIPTNAME=$( basename $0 )

# set some sane env defaults
umask 0022
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

### create the new ns and run this script inside
# note: caller should scrub the environment.
# (think fork())
if [[ $$ -ne 1 ]]; then
  unshare -mU -p -f -r --mount-proc=${1}/proc chroot $1 ${SCRIPTDIR}/${SCRIPTNAME} &
  MOUNTNSPID=$( jobs -p )
  pgrep -P $MOUNTNSPID
  echo $MOUNTNSPID
  disown -ah
  1>&-
  2>&-
  3>&-
  exit
fi


### set up prelim mounts and stuff.
mount -ttmpfs none /tmp
mount -ttmpfs none /root
mount -ttmpfs none /var
mkdir /tmp/.pun_tmp

# nginx won't run if this isn't present
# even though the config file overrides the compiled-in default.
mkdir -p /var/lib/ondemand-nginx/tmp

# spinlock until the caller finishes setting up our env.
if [[ $$ -eq 1 ]]; then
  for I in $( seq 3000 -1 1 ); do
    if [[ -f /tmp/release-spinlock ]]; then
      echo "RELEASE!"
      exec ${SCRIPTDIR}/setpriv --no-new-privs --bounding-set -all /opt/ood/ondemand/root/sbin/nginx -c /root/.pun_state/pun.conf
    fi
    if [[ $I -le 20 ]]; then
      echo "$I tries remaining"
    fi
    sleep 1
  done
  echo "Waited too long. Aborting."
fi

exit 1

