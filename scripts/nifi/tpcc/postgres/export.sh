#!/bin/bash

database_address=$1
tpcc_warehouses=$2
data_folder=$3

$(grep -q "^${database_address}" "${HOME}/.pgpass")
if [ $? -eq 0 ]; then
	## if the database configuration already exists then replace it with a new value
	sudo sed -i "s/^${database_address}.*/${database_address}:4432:postgres:postgres:postgres/g" ${HOME}/.pgpass
else
	## otherwise add the database configuration to pgpass
	echo "${database_address}:4432:postgres:postgres:postgres" | tee -a ${HOME}/.pgpass > /dev/null
fi
chmod 600 ${HOME}/.pgpass

function exportPartition() {
	mkdir -p ${data_folder}/${2}
	[ ! -f "${data_folder}/${2}/partition_${1}.dump" ] && pg_dump -Fc -h ${database_address} -p 4432 -U postgres -w -a -t customer_${1} -t history_${1} -t order_${1} -t new_order_${1} -t stock_${1} -t order_line_${1} > ${data_folder}/${2}/partition_${1}.dump
}

mkdir -p ${data_folder}/${tpcc_warehouses}
[ ! -f "${data_folder}/${tpcc_warehouses}/schema.dump" ] && pg_dump -Fc -h ${database_address} -p 4432 -U postgres -w --schema-only > ${data_folder}/${tpcc_warehouses}/schema.dump
[ ! -f "${data_folder}/${tpcc_warehouses}/warehouse.dump" ] && pg_dump -Fc -h ${database_address} -p 4432 -U postgres -w -a -t warehouse -t district -t item > ${data_folder}/${tpcc_warehouses}/warehouse.dump

partitions=$((${tpcc_warehouses} / 100))
for i in $(seq 1 $partitions); do
	partition=${i}
	folder=$((${i} * 100))
	exportPartition ${partition} ${folder} &
done
if ((${tpcc_warehouses} % 100)); then
	partition=$((${partitions} + 1))
	folder=${tpcc_warehouses}
	exportPartition ${partition} ${folder} &
fi
wait
