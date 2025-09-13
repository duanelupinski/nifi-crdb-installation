#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
database_workload=$1
database_address=$2
warehouses=$3
start=$4
duration=$5
concurrency=$6
cpus=$7
throughput=$8
terraform_path=$9
provider=${10}
key_name=${11}
key_user=${12}
if [[ ! -z ${key_name} && ! ${key_name} == /* ]]; then
    key_name=${terraform_path}/${key_name}
fi
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi

ssh-keygen -f ~/.ssh/known_hosts -R "${database_workload}"
command="$(cat <<-EOF
    \$(grep -q "^${database_address}" "\${HOME}/.pgpass")
    if [ \$? -eq 0 ]; then
        ## if the database configuration already exists then replace it with a new value
        sudo sed -i "s/^${database_address}:4432.*/${database_address}:4432:postgres:postgres:postgres/g" \${HOME}/.pgpass
    else
        ## otherwise add the database configuration to pgpass
        echo "${database_address}:4432:postgres:postgres:postgres" | tee -a \${HOME}/.pgpass > /dev/null
    fi
    chmod 600 \${HOME}/.pgpass

    python3 /home/\${USER}/execute-transactions.py ${database_address} ${warehouses} ${start} ${duration} ${concurrency} ${cpus} ${throughput}
EOF
)"
if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
    ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_workload} "sudo rm -rf execute-transactions.py"
    scp ${SCRIPT_DIR}/execute-transactions.py ${key_user}@${database_workload}:/home/${key_user}
    ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_workload} "${command}"
else
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_workload} "sudo rm -rf execute-transactions.py"
    scp -i ${key_name} ${SCRIPT_DIR}/execute-transactions.py ${key_user}@${database_workload}:/home/${key_user}
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_workload} "${command}"
fi
