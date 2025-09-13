#!/bin/bash

if [ -z "$4" ]; then
    count=$(jq -r "[.resources[] // {instances: []} | select(.type==\"$1\") // {instances: []} | .instances | length] | add" $3/terraform.tfstate)
else
    count=$(jq -r "[.resources[] // {instances: []} | select(.type==\"$1\" and .module==\"$4.$5[\\\"$6\\\"]\") // {instances: []} | .instances | length] | add" $3/terraform.tfstate)
fi
if [[ ${count} -lt 5 ]]; then
    echo 0
else
    echo "${count}"
fi
