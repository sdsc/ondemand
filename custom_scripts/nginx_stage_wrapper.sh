#!/bin/bash

echo $@ >> /tmp/params

/opt/ood/ondemand/root/usr/sbin/nginx "$@"
#(tail --pid=$! -f /dev/null; touch /tmp/done2) &
#pgrep -f trevorp.conf
