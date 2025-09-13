#!/bin/bash

database_address=$1
terraform_path=$2
provider=$3
key_name=$4
key_user=$5
if [[ ! -z ${key_name} && ! ${key_name} == /* ]]; then
    key_name=${terraform_path}/${key_name}
fi
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi

command="$(cat <<-EOF
	echo \$(lscpu | egrep '^CPU\\(s\\)') | cut -f2 -d' '
EOF
)"

if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
	ssh -q -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
else
	ssh -q -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
fi
