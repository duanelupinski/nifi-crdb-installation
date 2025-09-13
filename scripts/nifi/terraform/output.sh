#!/bin/bash

terraformPath=$1
testInstances=$2

export IFS=","
output={}
for instance in ${testInstances}; do
    name=$(echo ${instance} | sed -e 's/^[[:space:]]*//')
    value=$(jq ' .outputs.database_map.value | {"'${name}'": ."'${name}'"}' ${terraformPath}/terraform.tfstate)
    address=$(echo "${value}" | jq -r ".[\"${name}\"].address")
    if [[ ${address} != "null" ]]; then
        output=$(jq -n --argjson a "${output}" --argjson b "${value}" '$a + $b')
    fi
done

echo "${output}"
