#!/bin/bash

provider=$1
terraformPath=$2
terraformResource=$3
terraformResourceName=$4
testInstance=$5
scale=$6
keyName=$7
keyUser=$8
all=$9

if [[ ${provider} == 'aws' ]]; then
    export TF_VAR_region=$(aws configure get region)
    export TF_VAR_key=$(aws configure get aws_access_key_id)
    export TF_VAR_secret=$(aws configure get aws_secret_access_key)
elif [[ ${provider} == 'gcp' ]]; then
    export TF_VAR_region=$(gcloud config get compute/region)
    export TF_VAR_project=$(gcloud config get-value project)
fi
if [[ ! -z ${keyName} && ! ${keyName} = /* ]]; then
    export TF_VAR_ssh_key_name=${terraformPath}/${keyName}
	export TF_VAR_ssh_public_key=${terraformPath}/${keyName}.pub
    export TF_VAR_ssh_key_value=$(cat ${terraformPath}/${keyName}.pub)
else
    export TF_VAR_ssh_key_name=${keyName}
	export TF_VAR_ssh_public_key=${keyName}.pub
    export TF_VAR_ssh_key_value=$(cat ${keyName}.pub)
fi
if [[ ! -z ${keyUser} ]]; then
    export TF_VAR_vm_user=${keyUser}
fi
export TF_VAR_disk_scale=${scale}

checklock=0
while
    if [[ ! -z "$all" && $all = true ]]; then
        checklock=$(flock -w 1 -E 101 -e ${terraformPath}/nifi.lock -c "terraform -chdir=${terraformPath} destroy -auto-approve"; echo $?)
    else
        checklock=$(flock -w 1 -E 101 -e ${terraformPath}/nifi.lock -c "terraform -chdir=${terraformPath} destroy -target ${terraformResource}.${terraformResourceName}[\\\"${testInstance}\\\"] -auto-approve"; echo $?)
    fi
    [[ ${checklock} == 101 ]]
do
    sleep 1
done

echo ${checklock}
