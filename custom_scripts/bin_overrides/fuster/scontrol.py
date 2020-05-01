#!/usr/bin/python

from getpass import getuser
from select import select
from sh import ssh, ErrorReturnCode  # pip3 install sh
import os
import re
import sys
import syslog


SUBMISSION_NODE = 'login.fuster.sdsc.edu'
USER = os.environ['USER']

def run_remote_bin(remote_bin_path, *argv):
  output = None

  try:
    result = ssh(
      SUBMISSION_NODE,
      '-oBatchMode=yes',  # ensure that SSH does not hang waiting for a password that will never be sent
      remote_bin_path,  # the real sbatch on the remote
      *argv,  # any arguments that sbatch should get
      _err_to_out=True  # merge stdout and stderr
    )

    output = result.stdout.decode('utf-8')
    syslog.syslog(syslog.LOG_INFO, output)
  except ErrorReturnCode as e:
    output = e.stdout.decode('utf-8')
    syslog.syslog(syslog.LOG_INFO, output)
    print(output)
    sys.exit(e.exit_code)

  return output


def main():
  output = run_remote_bin(
    '/bin/scontrol',
    sys.argv[1:]
  )

  print(output)

if __name__ == '__main__':
  main()
