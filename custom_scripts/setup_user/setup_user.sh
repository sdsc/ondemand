#!/bin/bash

USERNAME=$1
USER_UID=$2
ACCESS_TOKEN_FILE=$3
JAIL_DIR=$4
MOUNT_PID=$5

# Note: we expect the caller to provide USER_UID since it may
# not be an account on the system... eventually.

# Logistics require stashing everything locally, since the oa4mp secret isn't in the container.
# Hopefully this doesn't last long.
umask 0077
CERT_WORK_DIR=$(mktemp -d /dev/shm/setup_user_XXXXXXXXXX)
if [[ -z ${CERT_WORK_DIR+x} ]]; then
  echo "Unable to create temp dir in /dev/shm" 1>&2
  exit 1
fi

CUSTOM_SCRIPTS_DIR=$( cd $( dirname $0 )/../; pwd)

CSR_CONFIG_PATH=/opt/ood/custom_scripts/setup_user/csr_config
KEY_PATH=$CERT_WORK_DIR/key.pem 
CSR_PATH=$CERT_WORK_DIR/req.pem 
CERT_PATH=$CERT_WORK_DIR/cert.pem 

GSI_SSH_PEM_PATH="${JAIL_DIR}/tmp/x509up_u${USER_UID}"


openssl genrsa -out $KEY_PATH 2048
openssl req -new -config "$CSR_CONFIG_PATH" -key "$KEY_PATH" -out "$CSR_PATH"

python3 $CUSTOM_SCRIPTS_DIR/setup_user/request_cert.py \
  "$USERNAME" \
  "$ACCESS_TOKEN_FILE" \
  "$KEY_PATH" \
  "$CSR_PATH" \
  "$CERT_PATH" &> "$CERT_WORK_DIR/log.txt"

# Copy key and cert to where gsi ssh is expecting it
# gsissh accepts key + cert concat to make things easier.
cat "$CERT_PATH" >> "$KEY_PATH"

# This needs to happen in the container since /tmp is 
# not available outside.
cat "$KEY_PATH" | ${CUSTOM_SCRIPTS_DIR}/ns/enter_ns.sh $MOUNT_PID tee $GSI_SSH_PEM_PATH >/dev/null
${CUSTOM_SCRIPTS_DIR}/ns/enter_ns.sh $MOUNT_PID chown $USERNAME:$USERNAME $GSI_SSH_PEM_PATH
${CUSTOM_SCRIPTS_DIR}/ns/enter_ns.sh $MOUNT_PID chmod 400 $GSI_SSH_PEM_PATH


# Remove the files that were used and are no longer needed
rm -rf "$CERT_WORK_DIR"
rm -f  "$ACCESS_TOKEN_FILE"

# stop here for now.
exit 0


# Mount users home directory from comet and fuster
REMOTE_USERNAME=`sudo /opt/ood/custom_scripts/grid-map_map.sh $GSI_SSH_PEM_PATH`
FUSTER_HOSTNAME="login.fuster.sdsc.edu"
COMET_HOSTNAME="comet.sdsc.edu"
REMOTE_HOME_DIR="/home/$REMOTE_USERNAME"

FUSTER_MOUNT_DIR="$OOD_USER_HOME/fuster"
COMET_MOUNT_DIR="$OOD_USER_HOME/comet"

mkdir -p $COMET_MOUNT_DIR
mkdir -p $FUSTER_MOUNT_DIR
chown $USERNAME:$USERNAME $COMET_MOUNT_DIR
chown $USERNAME:$USERNAME $FUSTER_MOUNT_DIR
chmod 700 $COMET_MOUNT_DIR
chmod 700 $FUSTER_MOUNT_DIR

su - $USERNAME -c "sshfs $FUSTER_HOSTNAME:$REMOTE_HOME_DIR $FUSTER_MOUNT_DIR"
su - $USERNAME -c "sshfs $COMET_HOSTNAME:$REMOTE_HOME_DIR $COMET_MOUNT_DIR"

# Set up a directory to store ood metadata on comet
su - $USERNAME -c "mkdir -p $COMET_MOUNT_DIR/.ood_portal"
