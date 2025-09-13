#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
node_addresses=$1
instance_name=$2
test_iteration=$3
metrics_path=$4
scenario=$5
testStart=$6
duration=$7
terraform_path=$8
provider=$9
key_name=${10}
key_user=${11}
if [[ ! -z ${key_name} && ! ${key_name} = /* ]]; then
    key_name=${terraform_path}/${key_name}
fi
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi
export IFS=","
hours=$(( (${duration} + 59) / 60 ))
minutes=$(( hours * 60 ))
startTime=$(date -d "${testStart}" +%s)

function copyFile {
    fileCopied=false
    while [[ $fileCopied == false ]]; do
        if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
            target=$(ssh -tt -o StrictHostKeyChecking=no ${key_user}@${1} "gzip -t ${2} && echo exists")
            if [[ -n ${target} ]]; then
                scp ${key_user}@${1}:${2} ${3}/
            fi
        else
            target=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${1} "gzip -t ${2} && echo exists")
            if [[ -n ${target} ]]; then
                scp -i ${key_name} ${key_user}@${1}:${2} ${3}/
            fi
        fi
        gzip -t ${3}/${4}
        copied=$?
        if [ $copied -ne 0 ]; then
            fileCopied=false
            if [[ ${5} == true ]]; then
                endTime=$(date -d "$(date)" +%s)
                waitMinutes="$(( ((${endTime} - ${startTime}) / 60) - (${minutes} / 2) ))"
                if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
                    running=$(ssh -tt -o StrictHostKeyChecking=no ${key_user}@${1} "ps cax | grep wrapper > /dev/null && echo running")
                else
                    running=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${1} "ps cax | grep wrapper > /dev/null && echo running")
                fi
                if [[ -z ${running} || ${waitMinutes} > ${minutes} ]]; then
                    command="$(cat <<-EOF
sudo chown -R \${USER}:\${USER} /tmp/wrapper_output/
sleep 30
cd /tmp/wrapper_output
tar czf wrapper_${1}_timedout.tar.gz wrapper_*/
EOF
)"
                    if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
                        ssh -tt -o StrictHostKeyChecking=no ${key_user}@${1} "${command}"
                    else
                        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${1} "${command}"
                    fi
                else
                    sleep 30
                fi
            else
                sleep 30
            fi
        else
            fileCopied=true
        fi
    done
}

i=0
for address in $node_addresses; do
    ssh-keygen -f ~/.ssh/known_hosts -R "${address}" > /dev/null
    command="$(cat <<-EOF
chmod +x /home/\${USER}/platform-profiler
mkdir -p /tmp/PlatformProfilerOutput
sudo /home/\${USER}/platform-profiler --osip localhost --output /tmp/PlatformProfilerOutput/
cd /tmp
tar czf PlatformProfilerOutput.tar.gz PlatformProfilerOutput/
EOF
)"
    if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/vbox/lib/platform-profiler/platform-profiler ${key_user}@${address}:/home/${key_user}
        ssh -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "${command}" 2>&1 < /dev/null &
    elif [[ ${provider} == 'aws' ]]; then
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "aws s3 cp s3://amd-profilers/platform-profiler /home/${key_user}/."
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "${command}" 2>&1 < /dev/null &
    elif [[ ${provider} == 'gcp' ]]; then
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "gcloud storage cp gs://amd-profilers/platform-profiler /home/${key_user}/."
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "${command}" 2>&1 < /dev/null &
    fi

    data_folder=${metrics_path}/${scenario}/test${test_iteration}/${instance_name}-${i}
    mkdir -p ${data_folder}
    copyFile ${address} /tmp/PlatformProfilerOutput.tar.gz ${data_folder} PlatformProfilerOutput.tar.gz false
    copyFile ${address} /tmp/wrapper_output/wrapper_*.tar.gz ${data_folder} wrapper_*.tar.gz true
    i=$((i+1))
done
