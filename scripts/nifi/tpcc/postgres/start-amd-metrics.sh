#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
address=$1
duration=$2
email=$3
workload=$4
terraform_path=$5
provider=$6
key_name=$7
key_user=$8
if [[ ! -z ${key_name} && ! ${key_name} == /* ]]; then
    key_name=${terraform_path}/${key_name}
fi
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi
hours=$(( (${duration} + 59) / 60 ))
ssh-keygen -f ~/.ssh/known_hosts -R "${address}"

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
        ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} "${command}"
        sleep 15
        region=$(ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} "aws configure get region")
    done
fi

command="$(cat <<-EOF
    chmod +x /home/\${USER}/wrapper
    sudo /home/\${USER}/wrapper --duration ${hours} --duration_metric Hours --email ${email} --osip localhost --tag ${workload}
EOF
)"
if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /mnt/vbox/lib/workload-profiler/wrapper ${key_user}@${address}:/home/${key_user}
    ssh -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "${command}" > wrapper.log 2>&1 < /dev/null &
elif [[ ${provider} == 'aws' ]]; then
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "aws s3 cp s3://amd-profilers/wrapper /home/${key_user}/."
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "${command}" > wrapper.log 2>&1 < /dev/null &
elif [[ ${provider} == 'gcp' ]]; then
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "gcloud storage cp gs://amd-profilers/wrapper /home/${key_user}/."
    ssh -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${address} nohup "${command}" > wrapper.log 2>&1 < /dev/null &
fi
