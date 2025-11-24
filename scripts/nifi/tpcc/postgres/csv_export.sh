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
	[ ! -f "${data_folder}/${2}/customer_${1}.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY customer_${1} TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${2}/customer_${1}.csv.gz
	[ ! -f "${data_folder}/${2}/history_${1}.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY history_${1} TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${2}/history_${1}.csv.gz
	[ ! -f "${data_folder}/${2}/order_${1}.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY order_${1} TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${2}/order_${1}.csv.gz
	[ ! -f "${data_folder}/${2}/new_order_${1}.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY new_order_${1} TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${2}/new_order_${1}.csv.gz
	[ ! -f "${data_folder}/${2}/stock_${1}.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY stock_${1} TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${2}/stock_${1}.csv.gz
	[ ! -f "${data_folder}/${2}/order_line_${1}.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY order_line_${1} TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${2}/order_line_${1}.csv.gz
}

mkdir -p ${data_folder}/${tpcc_warehouses}
pg_dump -h ${database_address} -p 4432 -U postgres -w --schema-only -t warehouse -t district -t item -t customer -t history -t order -t new_order -t stock -t order_line > ${data_folder}/${tpcc_warehouses}/schema.sql
sed -e '/set_config/ s/^/--/g' -i ${data_folder}/${tpcc_warehouses}/schema.sql
sed -e '/^SET/ s/^/--/g' -i ${data_folder}/${tpcc_warehouses}/schema.sql
sed -e 's/OWNER TO postgres/OWNER TO root/g' -i ${data_folder}/${tpcc_warehouses}/schema.sql
sed -e 's/CREATE UNLOGGED/CREATE/g' -i ${data_folder}/${tpcc_warehouses}/schema.sql
sed -e 's/PARTITION.*/;/g' -i ${data_folder}/${tpcc_warehouses}/schema.sql
[ ! -f "${data_folder}/${tpcc_warehouses}/warehouse.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY warehouse TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${tpcc_warehouses}/warehouse.csv.gz
[ ! -f "${data_folder}/${tpcc_warehouses}/district.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY district TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${tpcc_warehouses}/district.csv.gz
[ ! -f "${data_folder}/${tpcc_warehouses}/item.csv.gz" ] && psql -h ${database_address} -p 4432 -U postgres -w postgres -c "COPY item TO stdout DELIMITER ',' CSV;" | gzip > ${data_folder}/${tpcc_warehouses}/item.csv.gz

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
