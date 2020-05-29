#!/bin/bash -eu
# bind_mount_ns.sh
# 
# mount a directory in the ns
# provide the pid of the unshare process that created the ns
# don't use the pid of the ns pid=1 process
# 

# we'll need a pid, origin, target for sure.
#if [[ -z ${SUDO_USER+x} && ( -z ${1+x} || -z ${2+x} || -z ${3+x} ) ]]; then
#  echo "Usage: $0 <ppid in ns> <source> <target>" 1>&2
#  exit 1
#fi

# we'll need a numeric uid
if [[ ! ( "$1" =~ ^[0-9]+$ )]]; then
  echo "ppid does not look like a pid" 1>&2
  exit 1
fi

ppid=$1
shift

# origin must exist
if [[ ! -e $1 ]]; then
  echo "origin does not exist" 1>&2
  exit 1
fi
origin=$1
shift

target=$1
shift

# get uid/gid of process so we know what to feed to sudo.
# target should exist in some form?
if [[ -f $origin ]]; then
  dirs=$(dirname $target)
  /usr/local/bin/nent -m  -r --wd=/ -t $ppid mkdir -p $dirs 
  /usr/local/bin/nent -m  -r --wd=/ -t $ppid touch $target
elif [[ -d $origin ]]; then
  /usr/local/bin/nent -m -r --wd=/ -t $ppid mkdir -p $target
fi
/usr/local/bin/nent -m  -r --wd=/ -t $ppid mount $origin $target -obind,nosuid
