#!/bin/bash

jobname="postgres"
port="9187"
add=$1
databaseAddresses=$2
export IFS=","

if [ $add = true ]; then
  for address in $databaseAddresses; do
    config=$(/usr/local/bin/yq ".scrape_configs | (.[]) | (select(.job_name == \"node\"))" /etc/prometheus/prometheus.yml)
    if [[ -z "$config" ]]; then
      sudo /usr/local/bin/yq --inplace ".scrape_configs = .scrape_configs + {\"job_name\": \"node\", \"static_configs\": [{\"targets\": []}]}" /etc/prometheus/prometheus.yml
    fi

    target=$(/usr/local/bin/yq ".scrape_configs | (.[]) | select(.job_name == \"node\") | .static_configs | (.[]) | .targets | select(.[] == \"$address:9100\")" /etc/prometheus/prometheus.yml)
    if [[ -z "$target" ]]; then
      sudo /usr/local/bin/yq --inplace "with(.scrape_configs[]; select(.job_name == \"node\") | with(.static_configs[]; .targets += [\"$address:9100\"]))" /etc/prometheus/prometheus.yml
    fi

    config=$(/usr/local/bin/yq ".scrape_configs | (.[]) | (select(.job_name == \"$jobname\"))" /etc/prometheus/prometheus.yml)
    if [[ -z "$config" ]]; then
      sudo /usr/local/bin/yq --inplace ".scrape_configs = .scrape_configs + {\"job_name\": \"$jobname\", \"static_configs\": [{\"targets\": []}]}" /etc/prometheus/prometheus.yml
    fi

    target=$(/usr/local/bin/yq ".scrape_configs | (.[]) | select(.job_name == \"$jobname\") | .static_configs | (.[]) | .targets | select(.[] == \"$address:$port\")" /etc/prometheus/prometheus.yml)
    if [[ -z "$target" ]]; then
      sudo /usr/local/bin/yq --inplace "with(.scrape_configs[]; select(.job_name == \"$jobname\") | with(.static_configs[]; .targets += [\"$address:$port\"]))" /etc/prometheus/prometheus.yml
    fi
  done
else
  for address in $databaseAddresses; do
    sudo /usr/local/bin/yq --inplace "del(.scrape_configs | .[] | select(.job_name == \"node\") | .static_configs | .[] | .targets | .[] | select(. == \"$address:9100\"))" /etc/prometheus/prometheus.yml
    sudo /usr/local/bin/yq --inplace "del(.scrape_configs | .[] | select(.job_name == \"$jobname\") | .static_configs | .[] | .targets | .[] | select(. == \"$address:$port\"))" /etc/prometheus/prometheus.yml
  done
fi
