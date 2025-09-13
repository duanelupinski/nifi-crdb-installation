#!/bin/bash

provider=$1
terraformPath=$2
terraformResource=$3
terraformResourceName=$4
testInstances=$5
scale=$6
keyName=$7
keyUser=$8

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
export IFS=","

# try to spin up all instances at one time
count=0
targets=''
for instance in ${testInstances}; do
    ((count++))
    name=$(echo ${instance} | sed -e 's/^[[:space:]]*//')
    targets="${targets} -target ${terraformResource}.${terraformResourceName}[\\\"${name}\\\"] "
    if [ ${count} -ge 5 ]; then
        eval terraform -chdir=${terraformPath} apply ${targets} -auto-approve || true
        count=0
        targets=''
    fi
done
if [ ${count} -gt 0 ]; then
    eval terraform -chdir=${terraformPath} apply ${targets} -auto-approve || true
fi

# check if any instances failed
output=''
for instance in ${testInstances}; do
    name=$(echo ${instance} | sed -e 's/^[[:space:]]*//')
    value=$(jq ' .outputs.database_map.value | {"'${name}'": ."'${name}'"}' ${terraformPath}/terraform.tfstate)
    address=$(echo "${value}" | jq -r ".[\"${name}\"].address")
    if [[ ${address} == "null" ]]; then
        output="${output},${instance}"
    fi
done
testInstances=${output}

# and if so then spin them up individually
if [[ -n "${testInstances}" ]]; then
    for instance in ${testInstances}; do
        name=$(echo ${instance} | sed -e 's/^[[:space:]]*//')
        target="-target ${terraformResource}.${terraformResourceName}[\\\"${name}\\\"]"
        eval terraform -chdir=${terraformPath} apply ${target} -auto-approve || true
    done
fi
