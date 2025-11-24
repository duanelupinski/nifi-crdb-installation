#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
database_address=$1
psql_option=$2
psql_command=$3

lastMsg=0
result="first attempt"
job_id=0
original_command=$psql_command
while [ -n "$result" ]; do
    result=$(psql postgres -h ${database_address} -p 4432 -U postgres -w ${psql_option} "${psql_command}" 2>&1)
    errorCode=$(echo $?)
    if [[ $job_id == 0 && $result =~ ^"       job_id" ]]; then
        job_id=$(echo ${result} | cut -f3 -d' ')
        if [[ lastMsg != 1 ]]; then
            lastMsg=1
            echo ""
            echo "psql: ${psql_command}"
            echo "result: ${result}"
            echo "waiting for job ${job_id} to complete"
        fi
        psql_command="SHOW JOB WHEN COMPLETE ${job_id};"
    elif [[ $job_id != 0 && $result == *"failed"* ]]; then
        if [[ lastMsg != 2 ]]; then
            lastMsg=2
            echo ""
            echo "psql: ${original_command}"
            echo "result: ${result}"
            echo "retrying because job ${job_id} failed to execute"
        fi
        job_id=0
        psql_command=$original_command
    elif [[ $errorCode > 0 ]]; then
        if [[ lastMsg != 3 ]]; then
            lastMsg=3
            echo ""
            echo "psql: ${psql_command}"
            echo "result: ${result}"
            echo "retrying because command failed with error ${errorCode}"
        fi
        sleep 5
    else
        if [[ lastMsg != 4 ]]; then
            lastMsg=4
            echo ""
            echo "psql: ${psql_command}"
            echo "result: ${result}"
            echo "command completed successfully"
        fi
        result=""
    fi
done
