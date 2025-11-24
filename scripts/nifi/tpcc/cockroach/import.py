import sys
import requests
from urllib.parse import urljoin
import numpy as np
import pandas as pd
import os

if len(sys.argv) < 5:
    print('Usage: {0} instance_address (i.e. 192.168.1.32) warehouses (i.e. 10) data_folder (i.e. /mnt/vbox/data) scripts_folder (i.e. /home/jleelong/workspace/nifi-flows/scripts) terraform_path (i.e. /home/jleelong/workspace/nifi-flows/terraform/aws/tpcc) provider (i.e. aws) key_name (i.e. dev) key_user (i.e. debian)'.format(sys.argv[0]))
    sys.exit(1)

instance_address = sys.argv[1]
tpcc_warehouses = sys.argv[2]
data_folder = sys.argv[3]
scripts_folder = sys.argv[4]

if len(sys.argv) > 5:
    terraform_path = sys.argv[5]
else:
    terraform_path = ""

if len(sys.argv) > 6:
    provider = sys.argv[6]
else:
    provider = ""

if len(sys.argv) > 7:
    key_name = sys.argv[7]
else:
    key_name = ""

if len(sys.argv) > 8:
    key_user = sys.argv[8]
else:
    key_user = ""

# Check if import file exists
path = '{0}/{1}/schema.sql'.format(data_folder, tpcc_warehouses)
if not os.path.isfile(path):
    sys.stdout.write('false')
else:
    os.system('{0}/tpcc/cockroach/import.sh {1} {2} {3} {4} {5} {6} {7} > /dev/null'.format(scripts_folder, instance_address, tpcc_warehouses, data_folder, terraform_path, provider, key_name, key_user))
    sys.stdout.write('true')
