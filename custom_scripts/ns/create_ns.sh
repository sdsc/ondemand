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

### create the new ns and run this script inside
# (think fork())
if [[ $$ -ne 1 ]]; then
  unshare -mU -p -f -r --mount-proc=${1}/proc chroot $1 env -i PATH=${PATH} ${SCRIPTDIR}/${SCRIPTNAME} &
  MOUNTNSPID=$( jobs -p )
  pgrep -P $MOUNTNSPID
  disown -ah
  1>&-
  2>&-
  3>&-
  exit
fi


### set up prelim mounts and stuff.
mount -ttmpfs none /tmp
mount -ttmpfs none /root

# spinlock until the caller finishes setting up our env.
if [[ $$ -eq 1 ]]; then
  for I in $( seq 120 -1 1 ); do
    if [[ -f /tmp/release-spinlock ]]; then
      echo "RELEASE!"
      exec sleep 30
    fi
    if [[ $I -le 20 ]]; then
      echo "$I tries remaining"
    fi
    sleep 1
  done
  echo "Waited too long. Aborting."
fi

exit 1

