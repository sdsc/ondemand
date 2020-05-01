#!/usr/bin/python

from getpass import getuser
from select import select
from sh import ssh, ErrorReturnCode  # pip3 install sh
import syslog
import os
import re
import sys


SUBMISSION_NODE = 'login.fuster.sdsc.edu'
USER = os.environ['USER']

def run_remote_bin(remote_bin_path, *argv):
  output = None

  try:
    result = ssh(
      SUBMISSION_NODE,
      '-q',
      '-oBatchMode=yes',  # ensure that SSH does not hang waiting for a password that will never be sent
      remote_bin_path,  # the real sbatch on the remote
      *argv,  # any arguments that sbatch should get
      _err_to_out=True  # merge stdout and stderr
    )

    output = result.stdout.decode('utf-8')
    syslog.syslog(syslog.LOG_INFO, output)
  except ErrorReturnCode as e:
    output = e.stdout.decode('utf-8')
    syslog.syslog(syslog.LOG_INFO,output)
    print(output)
    sys.exit(e.exit_code)

  return output

def filter_args(args):
  new_args = list(filter(lambda arg: arg != '--noconvert', args))
  new_args = list(map(lambda arg: map_arg(arg), new_args))
  return new_args

def map_arg(string):
  if string == USER:
    return '$USER'
  else:
    return string

def main():
  output = run_remote_bin(
    '/bin/squeue',
    filter_args(sys.argv[1:])
  )

  print(output)

if __name__ == '__main__':
  main()
