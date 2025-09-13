#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
add=$1
databaseAddresses=$2

checklock=0
while
    checklock=$(flock -w 1 -E 101 -e ${SCRIPT_DIR}/monitor.lock -c "${SCRIPT_DIR}/monitor-prometheus.sh ${add} ${databaseAddresses}"; echo $?)
    [ ${checklock} -eq 101 ]
do
    sleep 1
done

echo ${checklock}
