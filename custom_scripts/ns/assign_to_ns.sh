#!/bin/bash -eu
# assign_to_ns.sh
# 
# recursively assign a single directory/file to the uid of a namespace
# process leader.
# provide the pid of the pid=1 process in the ns
# you want to assign ownership to.
#
# note: this command tries to avoid performing operations on symlinks.

# all targets need to start with this
base_prefix="/var/tmp/"

if [[ ! ( "$1" =~ ^[0-9]+$ )]]; then
  echo "ppid $1 does not look like a pid" 1>&2
  exit 1
fi

ppid=$1
shift

target=$1
shift

# just in case the caller did a '*'
if [[ ! -z ${1+x} ]]; then
  echo "Found unexpected extra arguments." 1>&2
  exit 1
fi

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
 
# test 4: target to reassign should not be a symlink nor have symlinks
# in it.
canonpath=$( readlink -e $target || true )
if [[ $canonpath != $target ]]; then
  echo "Target does not match its canonicalized path. Is there a symlink in there?" 1>&2
  exit 1
fi

# test 5: target should start with base prefix
if [[ $target != "${base_prefix}"* ]]; then
  echo "Target must start with ${base_prefix}" 1>&2
  exit 1
fi

chown -RPh -- :$pgid $target
chmod g+wrx -R -- $target
