import sys
import requests
from urllib.parse import urljoin
import numpy as np
import pandas as pd
import os

api_url = "http://localhost:9090"

# Base functions querying prometheus
def _do_query(path, params):
    resp = requests.get(urljoin(api_url, path), params=params)
    if not (resp.status_code // 100 == 200 or resp.status_code in [400, 422, 503]):
        resp.raise_for_status()

    response = resp.json()
    if response['status'] != 'success':
        raise RuntimeError('{errorType}: {error}'.format_map(response))

    return response['data']

# Range query
def query_range(query, start, end, step, timeout=None):
    params = {'query': query, 'start': start, 'end': end, 'step': step}
    params.update({'timeout': timeout} if timeout is not None else {})

    return _do_query('api/v1/query_range', params)

# Functions to get metrics definitions from an instance
def _get_metrics(instance, port):
    resp = requests.get(urljoin("http://{0}:{1}".format(instance, port), 'metrics'))
    if not (resp.status_code // 100 == 200 or resp.status_code in [400, 422, 503]):
        resp.raise_for_status()
    return resp.text

# Retrieve metrics info for node and postgres exporters
def metrics_info(instance):
    node_metrics = _get_metrics(instance, '9100')
    postgres_metrics = _get_metrics(instance, '9187')
    return node_metrics + postgres_metrics

if len(sys.argv) != 12:
    print('Usage: {0} instance_address (i.e. 192.168.1.32) instance_name (i.e. pgdb_medium) test_iteration (i.e. 1) start (i.e. 2023-06-20T02:52:47.014Z) end (i.e. 2023-06-20T02:53:48.149Z) warehouses (i.e. 10) connections (i.e. 64) cpus (i.e. 4) memory (i.e. 8192 mib) data_folder (i.e. /mnt/vbox/data) scenario (i.e. tiny)'.format(sys.argv[0]))
    sys.exit(1)

instance_address = sys.argv[1]
instance_name = sys.argv[2]
test_iteration = sys.argv[3]
start = sys.argv[4]
end = sys.argv[5]
tpcc_warehouses = sys.argv[6]
tpcc_connections = sys.argv[7]
tpcc_cpus = sys.argv[8]
tpcc_memory = sys.argv[9]
data_folder = sys.argv[10]
scenario = sys.argv[11]

# Perform our query
data = query_range('{{instance=~"{0}.*"}}'.format(instance_address), start, end, '15s')

# Prometheus range query giving a Pandas dataframe as output
counter = {}
frame = {}
for r in data['result']:
    metric = r['metric']['__name__']
    counter[metric] = counter.get(metric, 0) + 1
    job = r['metric']['job']
    field = metric + '#' + job
    counter[field] = counter.get(field, 0) + 1
    field += str(counter[field])
    if (counter[metric] == 1):
        field += '$'
    frame[field] = pd.Series((np.float64(v[1]) for v in r['values']),
                             index=(pd.Timestamp(v[0], unit='s') for v in r['values']))
    labels = set()
    labels.update(r['metric'].keys())
    labels.discard('__name__')
    labels.discard('instance')
    labels.discard('job')
    labels.discard('server')
    labels = sorted(labels)
    for label in labels:
        fieldlabel = field + '_' + label
        frame[fieldlabel] = pd.Series((r['metric'][label] for v in r['values']),
                                      index=(pd.Timestamp(v[0], unit='s') for v in r['values']))
df = pd.DataFrame(frame)
df['instance_address'] = instance_address
df['tpcc_warehouses'] = tpcc_warehouses
df['tpcc_connections'] = tpcc_connections
df['tpcc_cpus'] = tpcc_cpus
df['tpcc_memory'] = tpcc_memory
df['tpcc_scenario'] = scenario

# Save the metrics to a file
os.makedirs(os.path.expanduser('{0}/{1}/test{2}'.format(data_folder, scenario, test_iteration)), exist_ok=True)
df.to_csv(os.path.expanduser('{0}/{1}/test{2}/{3}.csv.gz'.format(data_folder, scenario, test_iteration, instance_name)), compression='gzip')
