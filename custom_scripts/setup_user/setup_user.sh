#!/bin/bash

USERNAME=$1
ACCESS_TOKEN=$2
CSR_CONFIG_PATH=/opt/ood/custom_scripts/setup_user/csr_config
USER_ID=`id -u $USERNAME`
OOD_USER_HOME=`eval echo "~$USERNAME"`
KEY_PATH=$OOD_CERT_DIR/key.pem 
CSR_PATH=$OOD_CERT_DIR/req.pem 
CERT_PATH=$OOD_CERT_DIR/cert.pem 
GSI_SSH_PEM_PATH=/tmp/x509up_u$USER_ID

if [ ! -f $GSI_SSH_PEM_PATH ] || ! openssl x509 -checkend 86400 -noout -in $GSI_SSH_PEM_PATH
then

  touch $KEY_PATH
  chmod 600 $KEY_PATH

  openssl genrsa -out $KEY_PATH 2048
  openssl req -new -config $CSR_CONFIG_PATH -key $KEY_PATH -out $CSR_PATH

  python3 /opt/ood/custom_scripts/setup_user/request_cert.py $USERNAME $ACCESS_TOKEN $KEY_PATH $CSR_PATH $CERT_PATH

  #Copy key and cert to where gsi ssh is expecting it
  cat $KEY_PATH > $GSI_SSH_PEM_PATH
  cat $CERT_PATH >> $GSI_SSH_PEM_PATH
  chown $USERNAME:$USERNAME $GSI_SSH_PEM_PATH
  chmod 600 $GSI_SSH_PEM_PATH

  # Remove the files that were used and are no longer needed
  rm $KEY_PATH
  rm $CERT_PATH
  rm $CSR_PATH

fi

# Mount user's home directory from comet and fuster
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
