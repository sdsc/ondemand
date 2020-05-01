import grp
import json
import os
from pathlib import Path
import pwd
import re
import sys
import urllib

from OpenSSL.SSL import FILETYPE_PEM
from OpenSSL.crypto import (dump_certificate_request, dump_privatekey, PKey, TYPE_RSA, X509Req)
import requests

def main():
    with open('/var/secrets/oauth_client.json') as config_file:
      config = json.load(config_file)

    username =      sys.argv[1]
    access_token =  sys.argv[2]
    key_path =      sys.argv[3]
    csr_path =      sys.argv[4]
    cert_path =     sys.argv[5]

    client_id =     config['id']
    cert_url =      config['url']
    client_secret = config['secret']

    #cert_dir = f'/var/ood/users/{username}/certs'
    #csr_path = os.path.join(cert_dir, f'req.pem')
    #key_path = os.path.join(cert_dir, f'key.pem')
    #cert_path = os.path.join(cert_dir, f'cert.pem')

    request_cert(access_token, client_id, client_secret, csr_path, cert_path, cert_url)

def request_cert(access_token, client_id, client_secret, csr_file_path, cert_path, cert_url):
    with open(csr_file_path, 'r') as f:
        lines = f.readlines()
        lines = lines[1:-1]
        csr_string = ''.join(lines)

        data = {
            'access_token': access_token,
            'client_id': client_id,
            'client_secret': client_secret,
            'certreq': csr_string
        }

        res = requests.post(cert_url, data=data)
        f = open(cert_path, 'w+')
        f.write(res.content.decode("utf-8"))
        f.close()

if __name__ == "__main__":
    main()
