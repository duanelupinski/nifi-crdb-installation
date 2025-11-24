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

function sshCommand {
    if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
        while ! ssh -o StrictHostKeyChecking=no ${key_user}@${database_address} "/bin/bash --login -c '${1}'"; do
            echo "ssh command ${1} failed, retrying..."
            sleep 5
        done
    else
        while ! ssh -i ${key_name} -o StrictHostKeyChecking=no ${key_user}@${database_address} "/bin/bash --login -c '${1}'"; do
            echo "ssh command ${1} failed, retrying..."
            sleep 5
        done
    fi
}

sshCommand "sudo mkdir -p /mnt/cockroach/import/${tpcc_warehouses} && sudo chmod -R 777 /mnt/cockroach/import/${tpcc_warehouses}"
sshCommand "nohup python3 -m http.server --directory /mnt/cockroach/import/ > \${HOME}/httpserver.log 2>&1 </dev/null &"
if [[ ${provider} == 'aws' ]]; then
    scp -i ${key_name} ${SCRIPT_DIR}/psql-command.sh ${key_user}@${database_address}:~/.
    region=""
    command="$(cat <<-EOF
            aws configure set aws_access_key_id "$(aws configure get aws_access_key_id)"
            aws configure set aws_secret_access_key "$(aws configure get aws_secret_access_key)"
            aws configure set region "$(aws configure get region)"
            aws configure set output_format "json"
EOF
    )"
    while [[ -z "${region}" ]]; do
        sshCommand "${command}"
        sleep 15
        region=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "aws configure get region")
    done
elif [[ ${provider} == 'gcp' ]]; then
    scp -i ${key_name} ${SCRIPT_DIR}/psql-command.sh ${key_user}@${database_address}:~/.
else
    scp ${SCRIPT_DIR}/psql-command.sh ${key_user}@${database_address}:~/.
fi

filesLoaded=false
while [[ $filesLoaded == false ]]; do
    if [[ ${provider} == 'aws' ]]; then
        sshCommand "aws s3 cp s3://cr-tpcc-export-${tpcc_warehouses}/schema.sql /mnt/cockroach/import/${tpcc_warehouses}/." &
        sshCommand "aws s3 cp s3://cr-tpcc-export-${tpcc_warehouses}/warehouse.csv.gz /mnt/cockroach/import/${tpcc_warehouses}/." &
        sshCommand "aws s3 cp s3://cr-tpcc-export-${tpcc_warehouses}/district.csv.gz /mnt/cockroach/import/${tpcc_warehouses}/." &
        sshCommand "aws s3 cp s3://cr-tpcc-export-${tpcc_warehouses}/item.csv.gz /mnt/cockroach/import/${tpcc_warehouses}/." &
    elif [[ ${provider} == 'gcp' ]]; then
        sshCommand "gcloud storage cp gs://cr-tpcc-export-${tpcc_warehouses}/schema.sql /mnt/cockroach/import/${tpcc_warehouses}/." &
        sshCommand "gcloud storage cp gs://cr-tpcc-export-${tpcc_warehouses}/warehouse.csv.gz /mnt/cockroach/import/${tpcc_warehouses}/." &
        sshCommand "gcloud storage cp gs://cr-tpcc-export-${tpcc_warehouses}/district.csv.gz /mnt/cockroach/import/${tpcc_warehouses}/." &
        sshCommand "gcloud storage cp gs://cr-tpcc-export-${tpcc_warehouses}/item.csv.gz /mnt/cockroach/import/${tpcc_warehouses}/." &
    else
        scp ${data_folder}/${tpcc_warehouses}/schema.sql ${key_user}@${database_address}:/mnt/cockroach/import/${tpcc_warehouses}/ &
        scp ${data_folder}/${tpcc_warehouses}/warehouse.csv.gz ${key_user}@${database_address}:/mnt/cockroach/import/${tpcc_warehouses}/ &
        scp ${data_folder}/${tpcc_warehouses}/district.csv.gz ${key_user}@${database_address}:/mnt/cockroach/import/${tpcc_warehouses}/ &
        scp ${data_folder}/${tpcc_warehouses}/item.csv.gz ${key_user}@${database_address}:/mnt/cockroach/import/${tpcc_warehouses}/ &
    fi
    wait
    sshCommand "gunzip -f /mnt/cockroach/import/${tpcc_warehouses}/*.csv.gz"
    filesLoaded=true
    sshCommand "test -e /mnt/cockroach/import/${tpcc_warehouses}/schema.sql"
    copied=$?
    if [ $copied -ne 0 ]; then
        filesLoaded=false
    fi
    sshCommand "test -e /mnt/cockroach/import/${tpcc_warehouses}/warehouse.csv"
    copied=$?
    if [ $copied -ne 0 ]; then
        filesLoaded=false
    fi
    sshCommand "test -e /mnt/cockroach/import/${tpcc_warehouses}/district.csv"
    copied=$?
    if [ $copied -ne 0 ]; then
        filesLoaded=false
    fi
    sshCommand "test -e /mnt/cockroach/import/${tpcc_warehouses}/item.csv"
    copied=$?
    if [ $copied -ne 0 ]; then
        filesLoaded=false
    fi
done

function loadFile() {
    sshCommand "sudo mkdir -p /mnt/cockroach/import/${2} && sudo chmod -R 777 /mnt/cockroach/import/${2}"
    filesLoaded=false
    while [[ $filesLoaded == false ]]; do
        if [[ ${provider} == 'aws' ]]; then
            sshCommand "aws s3 cp s3://cr-tpcc-export-${2}/${3}_${1}.csv.gz /mnt/cockroach/import/${2}/."
        elif [[ ${provider} == 'gcp' ]]; then
            sshCommand "gcloud storage cp gs://cr-tpcc-export-${2}/${3}_${1}.csv.gz /mnt/cockroach/import/${2}/."
        else
            scp ${data_folder}/${2}/${3}_${1}.csv.gz ${key_user}@${database_address}:/mnt/cockroach/import/${2}/
        fi
        sshCommand "gunzip -f /mnt/cockroach/import/${2}/${3}_${1}.csv.gz"
        filesLoaded=true
        sshCommand "test -e /mnt/cockroach/import/${2}/${3}_${1}.csv"
        copied=$?
        if [ $copied -ne 0 ]; then
            filesLoaded=false
        else
            sshCommand "touch /mnt/cockroach/import/${2}/${3}_${1}.loaded"
        fi
    done
}

function loadFiles() {
    partitions=$((${tpcc_warehouses} / 100))
    for i in $(seq 1 $partitions); do
        partition=${i}
        folder=$((${i} * 100))
        loadFile ${partition} ${folder} ${1}
    done
    if ((${tpcc_warehouses} % 100)); then
        partition=$((${partitions} + 1))
        folder=${tpcc_warehouses}
        loadFile ${partition} ${folder} ${1}
    fi
}

function loadAllFiles() {
    loadFiles "new_order"
    loadFiles "order"
    loadFiles "history"
    loadFiles "order_line"
    loadFiles "customer"
    loadFiles "stock"
}

function loadPartition() {
    sshCommand "sudo mkdir -p /mnt/cockroach/import/${2} && sudo chmod -R 777 /mnt/cockroach/import/${2}"
    filesLoaded=false
    while [[ $filesLoaded == false ]]; do
        filesLoaded=true
        sshCommand "test -e /mnt/cockroach/import/${2}/${3}_${1}.loaded"
        copied=$?
        if [ $copied -ne 0 ]; then
            filesLoaded=false
            sleep 5
        fi
    done
    command="$(cat <<-EOF

        if [[ ${provider} == 'gcp' ]]; then
            internal_address=\${INTERNAL_ADDRESS}
        else
            internal_address=${database_address}
        fi

        \${HOME}/psql-command.sh \${internal_address} -c "IMPORT INTO \"${3}\" CSV DATA (\"http://\${internal_address}:8000/${2}/${3}_${1}.csv\") WITH DETACHED;"
        sudo rm -rf /mnt/cockroach/import/${2}/${3}_${1}.csv
        sudo rm -rf /mnt/cockroach/import/${2}/${3}_${1}.loaded
EOF
    )"
    sshCommand "${command}"
}

function loadPartitions() {
    partitions=$((${tpcc_warehouses} / 100))
    for i in $(seq 1 $partitions); do
        partition=${i}
        folder=$((${i} * 100))
        loadPartition ${partition} ${folder} ${1}
        sleep 5
    done
    if ((${tpcc_warehouses} % 100)); then
        partition=$((${partitions} + 1))
        folder=${tpcc_warehouses}
        loadPartition ${partition} ${folder} ${1}
    fi
}

loadAllFiles &

statements=$(cat <<-EOF
drop table if exists order_line cascade;
drop table if exists stock cascade;
drop table if exists item cascade;
drop table if exists new_order cascade;
drop table if exists \"order\" cascade;
drop table if exists history cascade;
drop table if exists customer cascade;
drop table if exists district cascade;
drop table if exists warehouse cascade;
EOF
)
command="$(cat <<-EOF

    if [[ ${provider} == 'gcp' ]]; then
        internal_address=\${INTERNAL_ADDRESS}
    else
        internal_address=${database_address}
    fi

    \$(grep -q "^\${internal_address}" "\${HOME}/.pgpass")
    if [ \$? -eq 0 ]; then
        ## if the database configuration already exists then replace it with a new value
        sudo sed -i "s/^\${internal_address}:4432.*/\${internal_address}:4432:postgres:postgres:postgres/g" \${HOME}/.pgpass
    else
        ## otherwise add the database configuration to pgpass
        echo "\${internal_address}:4432:postgres:postgres:postgres" | tee -a \${HOME}/.pgpass > /dev/null
    fi
    chmod 600 \${HOME}/.pgpass

    \${HOME}/psql-command.sh \${internal_address} -c "${statements}"
    \${HOME}/psql-command.sh \${internal_address} -f /mnt/cockroach/import/${tpcc_warehouses}/schema.sql
    \${HOME}/psql-command.sh \${internal_address} -c "IMPORT INTO warehouse CSV DATA (\"http://\${internal_address}:8000/${tpcc_warehouses}/warehouse.csv\") WITH DETACHED;" &
    \${HOME}/psql-command.sh \${internal_address} -c "IMPORT INTO district CSV DATA (\"http://\${internal_address}:8000/${tpcc_warehouses}/district.csv\") WITH DETACHED;" &
    \${HOME}/psql-command.sh \${internal_address} -c "IMPORT INTO item CSV DATA (\"http://\${internal_address}:8000/${tpcc_warehouses}/item.csv\") WITH DETACHED;" &
    wait
    sudo rm -rf /mnt/cockroach/import/${tpcc_warehouses}/schema.sql
    sudo rm -rf /mnt/cockroach/import/${tpcc_warehouses}/warehouse.csv
    sudo rm -rf /mnt/cockroach/import/${tpcc_warehouses}/district.csv
    sudo rm -rf /mnt/cockroach/import/${tpcc_warehouses}/item.csv
EOF
)"
sshCommand "${command}"

loadPartitions "new_order"
loadPartitions "order"
loadPartitions "history"
loadPartitions "order_line"
loadPartitions "customer"
loadPartitions "stock"

command="$(cat <<-EOF

    if [[ ${provider} == 'gcp' ]]; then
        internal_address=\${INTERNAL_ADDRESS}
    else
        internal_address=${database_address}
    fi

    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE warehouse;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE district;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE item;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE new_order;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE \"order\";" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE history;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE order_line;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE customer;" &
    \${HOME}/psql-command.sh \${internal_address} -c "ANALYZE stock;" &
    wait
EOF
)"
sshCommand "${command}"

#command="$(cat <<-EOF
#
#    if [[ ${provider} == 'gcp' ]]; then
#        internal_address=\${INTERNAL_ADDRESS}
#    else
#        internal_address=${database_address}
#    fi
#
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE district VALIDATE CONSTRAINT warehouse_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE customer VALIDATE CONSTRAINT district_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE history VALIDATE CONSTRAINT customer_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE history VALIDATE CONSTRAINT district_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE \"order\" VALIDATE CONSTRAINT customer_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE new_order VALIDATE CONSTRAINT order_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE stock VALIDATE CONSTRAINT item_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE stock VALIDATE CONSTRAINT warehouse_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE order_line VALIDATE CONSTRAINT order_fk;" &
#    \${HOME}/psql-command.sh \${internal_address} -c "ALTER TABLE order_line VALIDATE CONSTRAINT stock_fk;" &
#    wait
#EOF
#)"
#sshCommand "${command}"
