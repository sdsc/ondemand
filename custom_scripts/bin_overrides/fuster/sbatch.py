#!/usr/bin/python

from getpass import getuser
from select import select
from sh import ssh, ErrorReturnCode  # pip3 install sh
import logging
import os
import re
import sys
import syslog

SUBMISSION_NODE = 'login.fuster.sdsc.edu'
USER = os.environ['USER']


def run_remote_sbatch(script, *argv):
  """
  @brief      SSH and submit the job from the submission node

  @param      script (str)  The script
  @param      argv (list<str>)    The argument vector for sbatch

  @return     output (str) The merged stdout/stderr of the remote sbatch call
  """

  output = None

  try:
    result = ssh(
      SUBMISSION_NODE,
      '-q',
      '-oBatchMode=yes',  # ensure that SSH does not hang waiting for a password that will never be sent
      '/bin/sbatch',  # the real sbatch on the remote
      *argv,  # any arguments that sbatch should get
      _in=script,  # redirect the script's contents into stdin
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

def load_script():
  """
  @brief      Loads a script from stdin.

  With OOD and Slurm the user's script is read from disk and passed to sbatch via stdin
  https://github.com/OSC/ood_core/blob/5b4d93636e0968be920cf409252292d674cc951d/lib/ood_core/job/adapters/slurm.rb#L138-L148

  @return     script (str) The script content
  """
  # Do not hang waiting for stdin that is not coming
  if not select([sys.stdin], [], [], 0.0)[0]:
    print('No script available on stdin!')
    sys.exit(1)

  return sys.stdin.read()


def main():
  """
  @brief      SSHs from web node to submit node and executes the remote sbatch.
  """
  output = run_remote_sbatch(
    load_script(),
    sys.argv[1:]
  )

  print(output)

if __name__ == '__main__':
  main()
