#!/bin/bash

MAP_FILE="/etc/grid-security/grid-mapfile"
CERT_FILE=$1

if [ ! -f $MAP_FILE ]; then
    echo "Map file '$MAP_FILE' not found"
    exit 1
fi

if [ ! -f $CERT_FILE ]; then
    echo "Cert file '$CERT_FILE' not found"
    exit 1
fi

SUBJECT=`openssl x509 -in $CERT_FILE -noout -subject`
READ_SUBJECT_COMMAND_RETURN_CODE=$?

if [ ! $READ_SUBJECT_COMMAND_RETURN_CODE -eq 0 ]; then
  echo "Error reading subject"
  exit 1
fi

SUBJECT=`sed -n -e 's/^.*subject= //p' <<< $SUBJECT`
SUBJECT="${SUBJECT//, //}"

MAPPING=`cat $MAP_FILE | fgrep -m1 "$SUBJECT"`
#USERNAME=`sed -n -e 's/^.*" //p' <<< $MAPPING`
USERNAME=`awk '{print $NF}' <<< $MAPPING`

echo $USERNAME
