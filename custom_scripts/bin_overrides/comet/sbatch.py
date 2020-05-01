#!/usr/bin/python

from getpass import getuser
from select import select
from sh import ssh, ErrorReturnCode  # pip3 install sh
import os
import re
import sys
import syslog


SUBMISSION_NODE = 'comet.sdsc.edu'
USER = os.environ['USER']


def run_remote_sbatch(script, *argv):

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


def filter_script(script):
  """
  @brief      Alter the script that the user is sending to sbatch

  This is a terrible fragile idea, but it is possible, so let's try it! We will set
  an environment variable and cleanup /tmp after the user.

  @param      script (str)  The script

  @return     script (str) The altered script
  """

  shebang = '#!/bin/bash\n'
  match = re.match('^(#!.+)\n', script)
  if match:
    shebang = match.group()
    script  = script.replace(shebang, '')

  return shebang + '''
  export THE_QUESTION='6*9=?'
  ''' + script + '''
  rm -rf /tmp 2>/dev/null
  '''


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
