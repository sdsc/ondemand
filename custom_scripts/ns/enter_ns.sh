#!/bin/bash -eu
# enter_ns.sh
# 
# execute a command inside an ns
# provide the pid of the pid=1 process in the ns
# you want to join.
# 

# we'll need just a numeric uid
if [[ ! ( "$1" =~ ^[0-9]+$ )]]; then
  echo "ppid does not look like a pid" 1>&2
  exit 1
fi

ppid=$1
shift

/usr/local/bin/nent -m -p -r --wd=/ -t $ppid "$@"
