#!/bin/bash
#
# create_ns.sh
# create a namespace and spin-lock in it until
# some important files appear.
#
# call this script as root and provide the
# username and numeric uid you want to run as later
#
# returns PID of the pid 1 inside the new namespace.
#

# need a new root directory.
# except when in the new namespace.
# We
if [[ "$3" == '' && $$ -ne 1 ]]; then
  echo "Usage: $0 <chroot directory> <user> <uid>" 1>&2
  exit 1
fi

# we'll need these later .. maybe
NEWROOT="$1"
NEWUSER="$2"
NEWUID="$3"

# where's this script running?
SCRIPTDIR=$( cd $(dirname $0) && pwd )
SCRIPTNAME=$( basename $0 )

# set some sane env defaults
umask 0022
#PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
#export PATH

### create the new ns and run this script inside
# note: caller should scrub the environment.
# (think fork())
if [[ $$ -ne 1 ]]; then
  nohup unshare -m -p -f --mount-proc=${1}/proc ${SCRIPTDIR}/${SCRIPTNAME} "$@" domount &>/dev/null &
  MOUNTNSPID=''
  while [[ -z "$MOUNTNSPID" ]]; do
    MOUNTNSPID=$( jobs -p )
    sleep 1
  done;
  pgrep -P $MOUNTNSPID
  echo $MOUNTNSPID
  disown -ah
  exit
fi


# The rest runs in the mount namespace


if [[ "$4" == 'domount' ]]; then
  ### set up prelim mounts and stuff.
  mount -ttmpfs none ${NEWROOT}/tmp
  chmod 1777 ${NEWROOT}/tmp
  mount -ttmpfs none ${NEWROOT}/root
  chmod 1777 ${NEWROOT}/root
  mount -ttmpfs none ${NEWROOT}/home
  chmod 0755 ${NEWROOT}/home
  mount -ttmpfs none ${NEWROOT}/var/lib/ondemand-nginx/tmp
  chmod 1777 ${NEWROOT}/var/lib/ondemand-nginx/tmp
  mkdir ${NEWROOT}/tmp/.pun_tmp
  chmod 1777 ${NEWROOT}/tmp/.pun_tmp
  mkdir -p ${NEWROOT}/dev/pts
  mount -tdevpts none ${NEWROOT}/dev/pts -o rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000

  ### set up home directories

  # base
  mkdir "${NEWROOT}/home/${NEWUSER}"
  chown "$NEWUSER" "${NEWROOT}/home/${NEWUSER}"
  chmod 0700 "${NEWROOT}/home/${NEWUSER}"
 
  # comet
  mkdir "${NEWROOT}/home/${NEWUSER}/comet"
  chown "$NEWUSER" "${NEWROOT}/home/${NEWUSER}/comet"
  chmod 0700 "${NEWROOT}/home/${NEWUSER}/comet"
 
  # fuster
  mkdir "${NEWROOT}/home/${NEWUSER}/fuster"
  chown "$NEWUSER" "${NEWROOT}/home/${NEWUSER}/fuster"
  chmod 0700 "${NEWROOT}/home/${NEWUSER}/fuster"


  # nginx won't run if this isn't present
  # even though the config file overrides the compiled-in default.
  #mkdir -p /var/lib/ondemand-nginx/tmp
  # exists already.

  exec chroot ${NEWROOT} ${SCRIPTDIR}/${SCRIPTNAME} "$NEWROOT" "$NEWUSER" "$NEWUID"
fi


# if we're still down here, that means we're in chrooted jail.
# spinlock until the caller finishes setting up our env.
if [[ $$ -eq 1 ]]; then
  for I in $( seq 3000 -1 1 ); do
    if [[ -f /tmp/release-spinlock ]]; then
      #echo -e "RELEASED!"
      export USER=${NEWUSER}
      export LOGNAME=${NEWUSER}     

      # last-minute sshfs mounts, which we do here so they get automatically cleaned up when
      # the pun exits.
      su - ${USER} -c "sshfs login.fuster.sdsc.edu: /home/${USER}/fuster -o nonempty"
      su - ${USER} -c "sshfs comet.sdsc.edu: /home/${USER}/comet -o nonempty"

      #exec sudo -u \#${NEWUID} v${SCRIPTDIR}/setpriv --no-new-privs --bounding-set -all,+setgid,+setuid,+chown /opt/ood/ondemand/root/sbin/nginx -c /root/.pun_state/pun.conf 

      exec ${SCRIPTDIR}/setpriv --no-new-privs --bounding-set -all,+setgid,+setuid,+chown,+dac_override /opt/ood/ondemand/root/sbin/nginx -c /root/.pun_state/pun.conf 


    fi
    if [[ $I -le 20 ]]; then
      echo "$I tries remaining"
    fi
    sleep 1
  done
  echo "Waited too long. Aborting."
fi

exit 1

