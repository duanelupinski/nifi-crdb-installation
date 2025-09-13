#!/bin/bash

database_address=$1
key_user=$2
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi

lines=$(grep -E 'nifi-node' /etc/hosts)
while read line; do 
        node=$(echo ${line} | cut -f2 -d' ')
        cat <<EOT | ssh -t -o StrictHostKeyChecking=no ${key_user}@${node} /bin/bash
sudo cat /home/nifi/.pgpass | grep -q "^${database_address}"
if [ \$? -eq 0 ]; then
        ## if the database configuration already exists then replace it with a new value
        sudo sed -i "s/^${database_address}.*/${database_address}:4432:postgres:postgres:postgres/g" /home/nifi/.pgpass
else
        ## otherwise add the database configuration to pgpass
        echo "${database_address}:4432:postgres:postgres:postgres" | sudo tee -a /home/nifi/.pgpass > /dev/null
fi
sudo chown nifi:nifi /home/nifi/.pgpass
sudo chmod 600 /home/nifi/.pgpass
EOT
done <<< "${lines}"
