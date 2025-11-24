#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
database_address=$1
tpcc_warehouses=$2
data_folder=$3
terraform_path=$4
provider=$5
key_name=$6
key_user=$7
if [[ ! -z ${key_name} && ! ${key_name} = /* ]]; then
    key_name=${terraform_path}/${key_name}
fi
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi

ssh-keygen -f ~/.ssh/known_hosts -R "${database_address}" > /dev/null

if [[ ${provider} == 'aws' ]]; then
    region=""
    while [[ -z "${region}" ]]; do
        command="$(cat <<-EOF
                aws configure set aws_access_key_id "$(aws configure get aws_access_key_id)"
                aws configure set aws_secret_access_key "$(aws configure get aws_secret_access_key)"
                aws configure set region "$(aws configure get region)"
                aws configure set output_format "json"
EOF
        )"
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
        sleep 15
        region=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "aws configure get region")
    done
fi

partitions=$((${tpcc_warehouses} / 100))
for i in $(seq 1 $partitions); do
    folder=$((${i} * 100))
    if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
        target=$(ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "test -d /mnt/postgres/import/${folder} && echo exists")
        if [[ -z ${target} ]]; then
            ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo mkdir -p /mnt/postgres/import/${folder} && sudo chmod -R 777 /mnt/postgres/import/${folder}"
            scp -r ${data_folder}/${folder}/ ${key_user}@${database_address}:/mnt/postgres/import/ &
        fi
    elif [[ ${provider} == 'aws' ]]; then
        target=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "test -d /mnt/postgres/import/${folder} && echo exists")
        if [[ -z ${target} ]]; then
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo mkdir -p /mnt/postgres/import/${folder} && sudo chmod -R 777 /mnt/postgres/import/${folder}"
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "aws s3 cp s3://pg-tpcc-export-${folder}/ /mnt/postgres/import/${folder} --recursive" &
        fi
    elif [[ ${provider} == 'gcp' ]]; then
        target=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "test -d /mnt/postgres/import/${folder} && echo exists")
        if [[ -z ${target} ]]; then
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo mkdir -p /mnt/postgres/import/${folder} && sudo chmod -R 777 /mnt/postgres/import/${folder}"
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "gcloud storage cp gs://pg-tpcc-export-${folder}/ /mnt/postgres/import/${folder} --recursive" &
        fi
    fi
done
if ((${tpcc_warehouses} % 100)); then
    folder=${tpcc_warehouses}
    if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
        target=$(ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "test -d /mnt/postgres/import/${folder} && echo exists")
        if [[ -z ${target} ]]; then
            ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo mkdir -p /mnt/postgres/import/${folder} && sudo chmod -R 777 /mnt/postgres/import/${folder}"
            scp -r ${data_folder}/${folder}/ ${key_user}@${database_address}:/mnt/postgres/import/ &
        fi
    elif [[ ${provider} == 'aws' ]]; then
        target=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "test -d /mnt/postgres/import/${folder} && echo exists")
        if [[ -z ${target} ]]; then
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo mkdir -p /mnt/postgres/import/${folder} && sudo chmod -R 777 /mnt/postgres/import/${folder}"
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "aws s3 cp s3://pg-tpcc-export-${folder}/ /mnt/postgres/import/${folder} --recursive" &
        fi
    elif [[ ${provider} == 'gcp' ]]; then
        target=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "test -d /mnt/postgres/import/${folder} && echo exists")
        if [[ -z ${target} ]]; then
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo mkdir -p /mnt/postgres/import/${folder} && sudo chmod -R 777 /mnt/postgres/import/${folder}"
            ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "gcloud storage cp gs://pg-tpcc-export-${folder}/ /mnt/postgres/import/${folder} --recursive" &
        fi
    fi
fi
wait

function loadPartition() {
    command="$(cat <<-EOF
        pg_restore -d postgres -e -j \$(echo \$(lscpu | egrep '^CPU\(s\)') | cut -f2 -d' ') -h ${database_address} -p 5432 -U postgres -w --data-only --disable-triggers /mnt/postgres/import/${2}/partition_${1}.dump
EOF
    )"
    if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
        ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
    else
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
    fi
}

statements=$(cat <<-EOF
drop table if exists order_line cascade;
drop table if exists stock cascade;
drop table if exists item cascade;
drop table if exists new_order cascade;
drop table if exists "order" cascade;
drop table if exists history cascade;
drop table if exists customer cascade;
drop table if exists district cascade;
drop table if exists warehouse cascade;
EOF
)
command="$(cat <<-EOF
    \$(grep -q "^${database_address}" "\${HOME}/.pgpass")
    if [ \$? -eq 0 ]; then
        ## if the database configuration already exists then replace it with a new value
        sudo sed -i "s/^${database_address}:4432.*/${database_address}:4432:postgres:postgres:postgres/g" \${HOME}/.pgpass
        sudo sed -i "s/^${database_address}:5432.*/${database_address}:5432:postgres:postgres:postgres/g" \${HOME}/.pgpass
    else
        ## otherwise add the database configuration to pgpass
        echo "${database_address}:4432:postgres:postgres:postgres" | tee -a \${HOME}/.pgpass > /dev/null
        echo "${database_address}:5432:postgres:postgres:postgres" | tee -a \${HOME}/.pgpass > /dev/null
    fi
    chmod 600 \${HOME}/.pgpass

    psql postgres -h ${database_address} -p 4432 -U postgres -w -c '${statements}'
    pg_restore -d postgres -e -j \$(echo \$(lscpu | egrep '^CPU\(s\)') | cut -f2 -d' ') -h ${database_address} -p 5432 -U postgres -w -s /mnt/postgres/import/${tpcc_warehouses}/schema.dump
    pg_restore -d postgres -e -j \$(echo \$(lscpu | egrep '^CPU\(s\)') | cut -f2 -d' ') -h ${database_address} -p 5432 -U postgres -w --data-only --disable-triggers /mnt/postgres/import/${tpcc_warehouses}/warehouse.dump
EOF
)"
if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
    ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
else
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
fi

partitions=$((${tpcc_warehouses} / 100))
for i in $(seq 1 $partitions); do
    partition=${i}
    folder=$((${i} * 100))
    loadPartition ${partition} ${folder} &
done
if ((${tpcc_warehouses} % 100)); then
    partition=$((${partitions} + 1))
    folder=${tpcc_warehouses}
    loadPartition ${partition} ${folder} &
fi
wait
if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
    ssh -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo rm -rf /mnt/postgres/import/"
else
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "sudo rm -rf /mnt/postgres/import/"
fi
