#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
provider=$1
terraformPath=$2
terraformResource=$3
terraformResourceName=$4
testInstances=$5
scale=$6
keyName=$7
keyUser=$8

checklock=0
while
    checklock=$(flock -w 1 -E 101 -e ${terraformPath}/nifi.lock -c "${SCRIPT_DIR}/applyTerraform.sh ${provider} ${terraformPath} ${terraformResource} ${terraformResourceName} \"${testInstances}\" ${scale} ${keyName} ${keyUser}"; echo $?)
    [[ ${checklock} == 101 ]]
do
    sleep 60
done

echo ${checklock}
