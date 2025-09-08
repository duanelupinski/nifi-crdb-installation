#!/bin/bash

## A POSIX variable - reset in case getopts has been used previously in the shell.
OPTIND=1

echo "setting up data structure to store key value map of cluster nodes in temp filesystem"
mapdir=$(mktemp -d)
trap 'rm -r ${mapdir}' EXIT

put() {
	[ "$#" != 3 ] && exit 1
	local mapname=$1; local key=$2; local value=$3
	[ -d "${mapdir}/${mapname}" ] || mkdir "${mapdir}/${mapname}"
	echo $value > "${mapdir}/${mapname}/${key}"
	#echo "put ${mapname} ${key} ${value}"
}

get() {
	[ "$#" != 2 ] && exit 1
	local mapname=$1; local key=$2
	cat "${mapdir}/${mapname}/${key}"
	#echo "get ${mapname} ${key}"
}

keys() {
	[ "$#" != 2 ] && exit 1
	local mapname=$1; local -n arr=$2
	arr=()
	if [ -d "${mapdir}/${mapname}/" ]; then
		for entry in "${mapdir}/${mapname}"/*; do
			arr+=("$(eval basename ${entry})")
		done
	fi
	#echo "keys ${mapname} ${arr[@]}"
}

APACHE_LATEST="https://dlcdn.apache.org"
APACHE_ARCHIVE="https://archive.apache.org/dist"

echo "setting default values for all parameters"
help=false
whoami=$(eval whoami | awk '{print $1}')
installer=debian
dist=${APACHE_ARCHIVE}
registry_host=""
registry_ip=""
postgres_version="42.5.4"
kafka_version="2.13-3.4.1"
kafka_user="kafka"
kafka_password="kafkapassword"
kafka_log_dir="/home/kafka/logs"
zookeeper_data_dir="/home/kafka/zookeeper"
nifi_version="1.22.0"
username="nifi"
password="nifipassword"
installation_folder="/home/${username}/"
sensitive_prop_key="/HbtLtRYy3wSMHAzafe+AyHv860za2eA"
flowfile_repo="/flow_repo"
database_repo="/data_repo"
content_repo=""
provenance_repo=""
memory="1g"
log_dir="/home/nifi/logs"
secure=false

echo "reading input parameters for the test"
while getopts "h?i:dr:p:k:u:w:l:z:N:I:U:W:P:F:D:C:O:M:L:SA:" opt; do
  case "${opt}" in
	h|\?) help=true;;
	i) installer=$OPTARG;;
	d) dist=$APACHE_ARCHIVE;;
	r) registry_host=$(echo $OPTARG | cut -f1 -d=)
	   registry_ip=$(echo $OPTARG | cut -f2 -d=)
	   ;;
	p) postgres_version=$OPTARG;;
	k) kafka_version=$OPTARG;;
	u) kafka_user=$OPTARG;;
	w) kafka_password=$OPTARG;;
	l) kafka_log_dir=$OPTARG;;
	z) zookeeper_data_dir=$OPTARG;;
	N) nifi_version=$OPTARG;;
	U) username=$OPTARG;;
	W) password=$OPTARG;;
	I) installation_folder=$OPTARG;;
	P) sensitive_prop_key=$OPTARG;;
	F) flowfile_repo=$OPTARG;;
	D) database_repo=$OPTARG;;
	C) content_repo=$OPTARG;;
	O) provenance_repo=$OPTARG;;
	M) memory=$OPTARG;;
	L) log_dir=$OPTARG;;
	S) secure=true;;
	A) authority=$OPTARG;;
  esac
done

## if help needed then print the menu and exit
if [ $help = true ]; then
	echo
	echo "usage: $0 -h|? [Show Help = false] -i [Intaller = debian] -d [Archive Dist = false] -r [Registry <hostname>=<ip.address>] -p [Postgres Version = 42.5.4] -k [Kafka Version = 2.13-3.4.1] -u [Kafka User = kafka] -w [Kafka Password = kafkapassword] -l [Kafka Log Dir = /home/kafka/logs] -z [Zookeeper Data Directory = /home/kafka/zookeeper] -N [NiFi Version = 1.22.0] -U [NiFi User = nifi] -W [NiFi Password = nifipassword] -I [Installation Folder = /home/${username}/] -P [Sensitive Prop Key = default value] -F [Flowfile Repository = /flow_repo] -D [Database Repository = /data_repo] -C [Content Repository?] -O [Provenance Repository?] -M [Memory = 1g] -L [Log Directory = /home/nifi/logs] -S [Is Secure = false] -A <Certificate Authority> existing-<id>:<hostname>=<ip.address> [existing-<id>:...] node-<id>:<hostname>=<ip.address> [node-<id>:...] contrepo-<id>:<mount>=<filesystem> [contrepo-<id>:...] provrepo-<id>:<mount>=<filesystem> [provrepo-<id>:...]"
	echo
	echo "This script is designed to install dependencies, configure and add nodes to a clustered NiFi environment that can be used to POC data flows for client workloads"
	echo
	echo "SWITCH PARAMETERS:"
	echo "-h|? Show Help:                   if provided then prints this menu"
	echo "-i   Installer:                   specifies the name of the user performing the installation, defaults to debian"
	echo "-d   Archive Dist:                use this flag if you want to retrieve package installation files from archive, defaults to false"
	echo "-r   Registry:                    specifies the hostname and IP address for the node where the registry is to be installed, i.e. registry=192.168.1.60"
	echo "-p   Postgres Version:            specifies the driver version of Postgres that should be used for connectivity, defaults to 42.2.19"
	echo "-k   Kafka Version:               specifies the software version of Kafka that should be used for streaming data, defaults to 2.13-3.0.0"
	echo "-u   Kafka User:                  specifies the account that will be used to install and run Kafka as a service, defaults to kafka"
	echo "-w   Kafka Password:              specifies the password used to login as the kafka user, defaults kafkapassword"
	echo "-l   Kafka Log Directory:         specifies the root disk location where kafka log files will be written to, defaults to /home/kafka/logs"
	echo "-z   Zookeeper Data Directory:    specifies the root disk location where zookeeper data files will be written to, defaults to /home/kafka/zookeeper"
	echo "-N   NiFi Version:                specifies the version of NiFi that should be installed, defaults to 1.20.0"
	echo "-U   NiFi User:                   specifies the account that will be used to install and run NiFi as a service, defaults nifi"
	echo "-W   NiFi Password:               specifies the password used to login as the nifi user, defaults nifipassword"
	echo "-I   Installation Folder:         sepcifies where the NiFi binaries will be installed for the NIFI_HOME enviornment variable, defaults to /home/${username}/"
	echo "-P   Sensitive Prop Key:          specifies a unique value used to derive a key for generating cipher text on sensitive properties, defaults to a hard-coded value"
	echo "-F   Flowfile Repository:         specifies the root disk location where flowfiles will be persistently stored, defaults to /flow_repo"
	echo "-D   Database Repository:         specifies the root disk location where database files will be persistently stored, defaults to /data_repo"
	echo "-C   Content Repository:          specifies the root disk location where content data will be persistently stored, if not specified then rely on separate mount points"
	echo "-O   Provenance Repository:       specifies the root disk location where data provenance will be persistently stored, if not specified then rely on separate mount points"
	echo "-M   Memory:                      specifies the heap size to allocate for nifi core processes, defaults to 1g but should be much larger for anything other than testing the install"
	echo "-L   Log Directory:               specifies the root disk location where log files will be written to, defaults to /home/nifi/logs"
	echo "-S   Secure:                      use this flag if you want certificates to enable TLS and user authentication, defaults false"
	echo "-A   Authority:                   specifies the certificate authority used for certificate signing requests"
	echo
	echo "ADDITIONAL PARAMETERS:"
	echo "existing:    for each existing node in the cluster provide the hostname and ip address of the node as existing-id:hostname=ip.address, the id must be a number starting at 1, i.e."
	echo "                 existing-1:nifi-pkg-1=192.168.86.27 existing-2:nifi-pkg-2=192.168.86.35 existing-3:nifi-pkg-3=192.168.86.38"
	echo "node:        for each new node to be added to the cluster provide the hostname and ip address of the node as node-id:hostname=ip.address, the id must be a number starting at 1, i.e."
	echo "                 node-4:nifi-pkg-1=192.168.86.41 node-2:nifi-pkg-5=192.168.86.42 node-6:nifi-pkg-3=192.168.86.43"
	echo "contrepo:    for each device allocated to store content, provide the filesystem and mount as contrepo-id:mount=filesystem, i.e."
	echo "                 contrepo-contS1R1:cont-repo1=/dev/sdb5 contrepo-contS1R2:cont-repo2=/dev/sdb6 contrepo-contS1R3:cont-repo3=/dev/sdb7"
	echo "provrepo:    for each device allocated to store data provenance, provide the filesystem and mount as provrepo-id:mount=filesystem, i.e."
	echo "                 provrepo-provS1R1:prov-repo1=/dev/sdb8 provrepo-provS1R2:/prov-repo2=/dev/sdb9"
	echo
	exit 0

## else get, report and check the remaining arguments
else
	shift $((OPTIND-1))
	[ "${1:-}" = "--" ] && shift
	
	if [[ -n "${registry_host}" ]]; then
		echo "adding the registry to the node configuration"
		put "all-id" $registry_host 0
		put "all" $registry_host $registry_ip
		put "existing-id" $registry_host 0
		put "existing" $registry_host $registry_ip
	fi
	
	for arg in "$@"; do
		qualifiers=$(echo $arg | cut -f1 -d=)
		mapinfo=$(echo $qualifiers | cut -f1 -d:)
		mapname=$(echo $mapinfo | cut -f1 -d-)
		keyid=$(echo $mapinfo | cut -f2 -d-)
		key=$(echo $qualifiers | cut -f2 -d:)
		value=$(echo $arg | cut -f2 -d=)
		put "${mapname}-id" $key $keyid
		put $mapname $key $value
		if [ $mapname = "existing" ] || [ $mapname = "node" ]; then
			put "all-id" $key $keyid
			put "all" $key $value
		fi
	done
	
	echo "printing parameter values to confim options used"
	echo "Hostname='$(hostname)'"
	echo "Who Am I='${whoami}'"
	echo "Installer='${installer}'"
	echo "Dist='${dist}'"
	echo "Registry Host='${registry_host}'"
	echo "Registry IP='${registry_ip}'"
	echo "Postgres Version='${postgres_version}'"
	echo "Kafka Version='${kafka_version}'"
	echo "Kafka User='${kafka_user}'"
	echo "Kafka Password='${kafka_password}'"
	echo "Kafka Log Directory='${kafka_log_dir}'"
	echo "Zookeeper Data Directory='${zookeeper_data_dir}'"
	echo "NiFi Version='${nifi_version}'"
	echo "NiFi User='${username}'"
	echo "NiFi Password='${password}'"
	echo "Installation Folder='${installation_folder}'"
	echo "Sensitive Prop Key='$(eval echo ${sensitive_prop_key} | sed "s/./x/g")'"
	echo "Flowfile Repository='${flowfile_repo}'"
	echo "Database Repository='${database_repo}'"
	echo "Content Repository='${content_repo}'"
	echo "Provenance Repository='${provenance_repo}'"
	echo "Memory='${memory}'"
	echo "Log Directory='${log_dir}'"
	echo "Is Secure='${secure}'"
	echo "Certificate Authority='${authority}'"
	
	echo "Existing Nodes:"
	keys "existing" exists
	for host in ${exists[@]}; do
		echo "  existing-$(get existing-id ${host}):${host}=$(get existing ${host})"
	done
	
	echo "New Nodes:"
	keys "node" nodes
	for host in ${nodes[@]}; do
		echo "  node-$(get node-id ${host}):${host}=$(get node ${host})"
	done
	
	echo "All Nodes:"
	keys "all" all
	for host in ${all[@]}; do
		echo "  all-$(get all-id ${host}):${host}=$(get all ${host})"
	done
	
	echo "Content Repos:"
	keys "contrepo" contrepos
	for mnt in ${contrepos[@]}; do
		echo "  contrepo-$(get "contrepo-id" ${mnt}):${mnt}=$(get "contrepo" ${mnt})"
	done
	
	echo "Provenance Repos:"
	keys "provrepo" provrepos
	for mnt in ${provrepos[@]}; do
		echo "  provrepo-$(get "provrepo-id" ${mnt}):${mnt}=$(get "provrepo" ${mnt})"
	done
	
	echo "checking for invalid input and report any errors"
	valid=true
	if [[ -z "${installer}" ]]; then
		echo "ERROR: installer not provided"
		valid=false
	fi
	if [[ -z "${dist}" ]]; then
		echo "ERROR: dist not provided"
		valid=false
	fi
	if [[ -z "${postgres_version}" ]]; then
		echo "ERROR: postgres version not provided"
		valid=false
	fi
	if [[ -z "${kafka_version}" ]]; then
		echo "ERROR: kafka version not provided"
		valid=false
	fi
	if [[ -z "${kafka_user}" ]]; then
		echo "ERROR: kafka user not provided"
		valid=false
	fi
	if [[ -z "${kafka_password}" ]]; then
		echo "ERROR: kafka password not provided"
		valid=false
	fi
	if [[ -z "${kafka_log_dir}" ]]; then
		echo "ERROR: kafka log dir not provided"
		valid=false
	fi
	if [[ -z "${zookeeper_data_dir}" ]]; then
		echo "ERROR: zookeeper data dir not provided"
		valid=false
	fi
	if [[ -z "${nifi_version}" ]]; then
		echo "ERROR: nifi version not provided"
		valid=false
	fi
	if [[ -z "${username}" ]]; then
		echo "ERROR: nifi user not provided"
		valid=false
	fi
	if [[ -z "${password}" ]]; then
		echo "ERROR: nifi password not provided"
		valid=false
	fi
	if [[ -z "${installation_folder}" ]]; then
		echo "ERROR: installation folder not provided"
		valid=false
	fi
	if [[ -z "${sensitive_prop_key}" ]]; then
		echo "ERROR: sensitive prop key not provided"
		valid=false
	fi
	if [[ -z "${flowfile_repo}" ]]; then
		echo "ERROR: flowfile repository not provided"
		valid=false
	fi
	if [[ -z "${database_repo}" ]]; then
		echo "ERROR: database repository not provided"
		valid=false
	fi
	if [[ -z "${content_repo}" ]] && [[ ${#contrepos[@]} -eq 0 ]]; then
		echo "ERROR: either a default content repository location or mount points must be provided"
		valid=false
	fi
	if [[ ! -z "${content_repo}" ]] && [[ ${#contrepos[@]} -gt 0 ]]; then
		echo "ERROR: either a default content repository location or mount points can be provided, but not both"
		valid=false
	fi
	if [[ -z "${provenance_repo}" ]] && [[ ${#provrepos[@]} -eq 0 ]]; then
		echo "ERROR: either a default provenance repository location or mount points must be provided"
		valid=false
	fi
	if [[ ! -z "${provenance_repo}" ]] && [[ ${#provrepos[@]} -gt 0 ]]; then
		echo "ERROR: either a default provenance repository location or mount points can be provided, but not both"
		valid=false
	fi
	if [[ -z "${memory}" ]]; then
		echo "ERROR: memory allocation not provided"
		valid=false
	fi
	if [[ -z "${log_dir}" ]]; then
		echo "ERROR: log directory not provided"
		valid=false
	fi
	if [[ -z "${secure}" ]]; then
		echo "ERROR: is secure not provided"
		valid=false
	fi
	if [[ -z "${authority}" ]]; then
		echo "ERROR: certificate authority not provided"
		valid=false
	fi
	if [[ ${#nodes[@]} -lt 1 ]]; then
		echo "ERROR: at least 1 server node is required to scale the nifi cluster"
		valid=false
	fi
	if [ $valid = false ]; then
		exit 1
	fi
fi

#<<'###BLOCK-DONE'
###BLOCK-DONE

echo "checking status of SSH to execute the script on the other nodes in the cluster"
which nmap &> /dev/null || sudo apt-get install -y nmap
for host in ${all[@]}; do
	hostip=$(get all ${host})
	remote="${installer}@${hostip}"
	checkssh=$(nmap ${hostip} -PN -p ssh | grep open)
	if [[ ! -z "${checkssh}" ]]; then
		identity="${whoami}@$(hostname)"
		result=$(ssh ${remote} "grep -q \"${identity}\$\" .ssh/authorized_keys; echo \$?")
		if [ ${result} -ne 0 ]; then
			key="$(<~/.ssh/id_rsa.pub)"
			ssh ${remote} "echo '${key}' >> .ssh/authorized_keys"
		fi
		echo "INFO: ssh enabled for ${remote} and script will be executed remotely"
	else
		echo "ERROR: ssh not enabled on server and the installation cannot proceed on ${remote}"
		exit 1
	fi
done

echo "updating hostnames to include nodes in the cluster..."
for host in ${all[@]}; do
	prev=127.0.0.1
	next=127.0.1.1
	newLine=$(printf "%-15s %s" ${next} ${host})
	command="$(cat <<-EOF
		\$(grep -q ${next} /etc/hosts)
		if [ \$? -ne 0 ]; then
			sudo sed -i "/^${prev}.*/a\\${newLine}" /etc/hosts
		fi
	EOF
	)"
	remote="${installer}@$(get all ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
	
	prev=127.0.1.1
	for node in ${all[@]}; do
		next=$(get all ${node})
		newLine=$(printf "%-15s %s" ${next} ${node})
		command="$(cat <<-EOF
			\$(grep -q ${next} /etc/hosts)
			if [ \$? -ne 0 ]; then
				sudo sed -i "/^${prev}.*/a\\${newLine}" /etc/hosts
			fi
		EOF
		)"
		remote="${installer}@$(get all ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
		prev=${next}
	done
done

echo "updating package installer and upgrading versions..."
for host in ${nodes[@]}; do
	command="sudo apt update && sudo apt upgrade"
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "installing the firewall and configuring default policies..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			which ufw &> /dev/null || sudo apt-get install -y ufw
			sudo ufw default deny incoming
			sudo ufw default allow outgoing
			#sudo ufw allow from $(hostname -i) to any port 22 proto tcp
			sudo ufw allow ssh
			if [ ${secure} = true ]; then
				#sudo ufw allow from $(hostname -i) to any port 9443
				sudo ufw allow 9443
			else
				#sudo ufw allow from $(hostname -i) to any port 8080
				sudo ufw allow 8080
			fi
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "updating firewall rules to enable communication between nodes..."
for host in ${all[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		for node in ${all[@]}; do
			if [[ ${node} != ${registry_host} ]]; then
				if [[ ${host} != ${node} ]]; then
					nodeip=$(get all ${node})
					command="$(cat <<-EOF
						sudo ufw allow from ${nodeip} to any port 9092
						sudo ufw allow from ${nodeip} to any port 2181
						sudo ufw allow from ${nodeip} to any port 2888
						sudo ufw allow from ${nodeip} to any port 3888
						if [ ${secure} = true ]; then
							sudo ufw allow from ${nodeip} to any port 10443
							sudo ufw allow from ${nodeip} to any port 11443
						else
							sudo ufw allow from ${nodeip} to any port 9998
							sudo ufw allow from ${nodeip} to any port 9997
						fi
						sudo ufw allow from ${nodeip} to any port 6342
						sudo ufw allow from ${nodeip} to any port 4557
					EOF
					)"
					remote="${installer}@$(get all ${host})"
					echo "ssh -t ${remote} \"${command}\""
					ssh -t ${remote} "${command}"
				fi
			fi
		done
		command="$(cat <<-EOF
			sudo ufw disable
			echo y | sudo ufw enable
			sudo ufw status verbose
		EOF
		)"
		remote="${installer}@$(get all ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "installing postgres drivers for version ${postgres_version}..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			which wget &> /dev/null || sudo apt-get install -y wget
			sudo rm /usr/local/var/postgres/postgresql-*.jar
			sudo wget -P /usr/local/var/postgres https://jdbc.postgresql.org/download/postgresql-${postgres_version}.jar
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "installing java version 11..."
for host in ${nodes[@]}; do
	command="$(cat <<-EOF
		java_version=""
		if type -p java; then
			echo "found java executable in PATH"
			_java=java
		elif [[ -n \${JAVA_HOME} ]] && [[ -x \${JAVA_HOME}/bin/java ]];  then
			echo "found java executable in \${JAVA_HOME}"
			_java=\${JAVA_HOME}/bin/java
		else
			echo "no java found"
		fi
		
		## if java was found then grab the version number
		if [[ \${_java} ]]; then
			java_version=\$(\${_java} -version 2>&1 | awk -F '"' '/version/ {print \$2}')
			echo "java version is \${java_version}"
		fi
		
		## if the current java version is not 11 then install it
		if [[ \${java_version} != 11* ]]; then
			echo "installing java version 11..."
			sudo apt-get install -y openjdk-11-jre-headless
		fi
		
		## remove /bin/java from java home and escape the forward slashes in the java home path before storing in the environment
		java_link=\$(eval readlink -f /usr/bin/java)
		java_home=\${java_link//"/bin/java"}
		java_home_esc=\$(eval echo \${java_home} | sed 's/\//\\\\\//g')
		\$(grep -q ^JAVA_HOME= /etc/environment)
		if [ \$? -eq 0 ]; then
			## if the environment points to another java home then replace it with the latest
			echo "updating java home in the environment..."
			sudo sed -i "s/^JAVA_HOME=.*/JAVA_HOME=\${java_home_esc}/g" /etc/environment
		else
			## otherwise add java home to the environment
			echo "adding java home to the environment..."
			
			## make sure we have a new line in our file
			file=/etc/environment
			if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
				echo "new line at end of \${file}!"
			else
				echo "" | sudo tee -a \${file} > /dev/null
			fi
			
			echo JAVA_HOME=\${java_home} | sudo tee -a /etc/environment > /dev/null
			
			## and reload the java home environment variable
			. /etc/environment
			echo "JAVA_HOME=\${JAVA_HOME}"
		fi
	EOF
	)"
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "installing zookeeper and kafka services..."
for host in ${nodes[@]}; do
	hostid=$(get node-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${hostid} <= 3 )); then
		hostip=$(get node ${host})
		command="$(cat <<-EOF
			## create a separate user for kafka
			\$(grep -q "^${kafka_user}" "/etc/passwd" > /dev/null)
			if [ \$? -ne 0 ]; then
				pass=\$(perl -e 'print crypt($ARGV[0], "password")' ${kafka_password})
				sudo useradd -m -p \${pass} ${kafka_user}
				[ \$? -eq 0 ] && echo "${kafka_user} user has been added to system!" || echo "Failed to add ${kafka_user} user!"
				sudo adduser ${kafka_user} sudo
			fi
			
			## download and extract the kafka package
			if [ ! -d "/home/${kafka_user}/kafka_${kafka_version}/" ]; then
				echo "installing kafka binaries for version ${kafka_version}..."
				if [ ! -f "/home/${kafka_user}/kafka_${kafka_version}.tgz" ]; then
					sudo runuser -l ${kafka_user} -c 'wget -P /home/${kafka_user}/ ${dist}/kafka/\$(echo ${kafka_version} | cut -f2 -d-)/kafka_${kafka_version}.tgz'
				fi
				sudo runuser -l ${kafka_user} -c 'tar -xvzf /home/${kafka_user}/kafka_${kafka_version}.tgz -C /home/${kafka_user}/'
			fi
			
			## make sure we have a new line at the end of our files before we append anything
			file="/home/${kafka_user}/kafka_${kafka_version}/config/server.properties"
			if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
				echo "new line at end of \${file}!"
			else
				echo \"\" | sudo tee -a \${file} > /dev/null
			fi
			file="/home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties"
			if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
				echo "new line at end of \${file}!"
			else
				echo \"\" | sudo tee -a \${file} > /dev/null
			fi
			
			\$(grep -q "^delete.topic.enable=" "/home/${kafka_user}/kafka_${kafka_version}/config/server.properties")
			if [ \$? -eq 0 ]; then
				## if the opton already exists then replace it with a new value
				sudo sed -i "s/^delete.topic.enable=.*/delete.topic.enable=true/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			else
				## otherwise add the option to the server properties
				echo "delete.topic.enable=true" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/server.properties > /dev/null
			fi
			\$(grep -q "^auto.create.topics.enable=" "/home/${kafka_user}/kafka_${kafka_version}/config/server.properties")
			if [ \$? -eq 0 ]; then
				## if the opton already exists then replace it with a new value
				sudo sed -i "s/^auto.create.topics.enable=.*/auto.create.topics.enable=true/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			else
				## otherwise add the option to the server properties
				echo "auto.create.topics.enable=true" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/server.properties > /dev/null
			fi
			sudo sed -i "s/^broker.id=.*/broker.id=${hostid}/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			\$(grep -q "^#listeners=" "/home/${kafka_user}/kafka_${kafka_version}/config/server.properties")
			if [ \$? -eq 0 ]; then
				## if the opton is commented out then update it and replace the value
				sudo sed -i "s/^#listeners=.*/listeners=PLAINTEXT:\/\/0.0.0.0:9092/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			else
				## otherwise just replace the value
				sudo sed -i "s/^listeners=.*/listeners=PLAINTEXT:\/\/0.0.0.0:9092/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			fi
			\$(grep -q "^#advertised.listeners=" "/home/${kafka_user}/kafka_${kafka_version}/config/server.properties")
			if [ \$? -eq 0 ]; then
				## if the opton is commented out then update it and replace the value
				sudo sed -i "s/^#advertised.listeners=.*/advertised.listeners=PLAINTEXT:\/\/${hostip}:9092/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			else
				## otherwise just replace the value
				sudo sed -i "s/^advertised.listeners=.*/advertised.listeners=PLAINTEXT:\/\/${hostip}:9092/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			fi
			\$(grep -q "^default.replication.factor=" "/home/${kafka_user}/kafka_${kafka_version}/config/server.properties")
			if [ \$? -eq 0 ]; then
				## if the opton already exists then replace it with a new value
				sudo sed -i "s/^default.replication.factor=.*/default.replication.factor=3/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			else
				## otherwise add the option to the server properties
				echo "default.replication.factor=3" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/server.properties > /dev/null
			fi
			\$(grep -q "^min.insync.replicas=" "/home/${kafka_user}/kafka_${kafka_version}/config/server.properties")
			if [ \$? -eq 0 ]; then
				## if the opton already exists then replace it with a new value
				sudo sed -i "s/^min.insync.replicas=.*/min.insync.replicas=1/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			else
				## otherwise add the option to the server properties
				echo "min.insync.replicas=1" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/server.properties > /dev/null
			fi
			sudo runuser -l ${kafka_user} -c 'mkdir -p ${kafka_log_dir}'
			log_dir_esc=\$(eval echo ${kafka_log_dir} | sed 's/\//\\\\\//g')
			sudo sed -i "s/^log.dirs=.*/log.dirs=\${log_dir_esc}/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "updating zookeeper configuration with node details..."
zkconnstr=""
for host in ${all[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		for node in ${all[@]}; do
			nodeid=$(get all-id ${node})
			if [[ ${node} != ${registry_host} ]] && (( ${nodeid} <= 3 )); then
				nodeip=$(get all ${node})
				if [[ ${node} == ${host} ]]; then
					## update the node connection string once for each host
					zkconnstr+="${nodeip}:2181,"
					nodeip=0.0.0.0
				fi
				command="$(cat <<-EOF
					\$(grep -q "^server.${nodeid}" "/home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties")
					if [ \$? -eq 0 ]; then
						## if the server is already listed then update the node details
						sudo sed -i "s/^server.${nodeid}.*/server.${nodeid}=${nodeip}:2888:3888/g" /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties
					else
						## otherwise add the node to the zookeeper configuration
						echo "server.${nodeid}=${nodeip}:2888:3888" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties > /dev/null
					fi
				EOF
				)"
				remote="${installer}@$(get all ${host})"
				echo "ssh -t ${remote} \"${command}\""
				ssh -t ${remote} "${command}"
			fi
		done
	fi
done

echo "configuring zookeeper properties for kafka..."
for host in ${all[@]}; do
	nodeid=$(get all-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${nodeid} <= 3 )); then
		command="$(cat <<-EOF
			sudo sed -i "s/^zookeeper.connect=.*/zookeeper.connect=${zkconnstr::-1}\/kafka/g" /home/${kafka_user}/kafka_${kafka_version}/config/server.properties
			\$(grep -q "^tickTime=" "/home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties")
			if [ \$? -eq 0 ]; then
				## if the tickTime is already listed then update the property value
				sudo sed -i "s/^tickTime=.*/tickTime=2000/g" /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties
			else
				## otherwise add the tickTime property to the zookeeper configuration
				echo "tickTime=2000" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties > /dev/null
			fi
			\$(grep -q "^initLimit=" "/home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties")
			if [ \$? -eq 0 ]; then
				## if the initLimit is already listed then update the property value
				sudo sed -i "s/^initLimit=.*/initLimit=10/g" /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties
			else
				## otherwise add the initLimit property to the zookeeper configuration
				echo "initLimit=10" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties > /dev/null
			fi
			\$(grep -q "^syncLimit=" "/home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties")
			if [ \$? -eq 0 ]; then
				## if the syncLimit is already listed then update the property value
				sudo sed -i "s/^syncLimit=.*/syncLimit=5/g" /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties
			else
				## otherwise add the syncLimit property to the zookeeper configuration
				echo "syncLimit=5" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties > /dev/null
			fi
			\$(grep -q "^4lw.commands.whitelist=" "/home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties")
			if [ \$? -eq 0 ]; then
				## if the 4lw.commands.whitelist is already listed then update the property value
				sudo sed -i "s/^4lw.commands.whitelist=.*/4lw.commands.whitelist=*/g" /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties
			else
				## otherwise add the syncLimit property to the zookeeper configuration
				echo "4lw.commands.whitelist=*" | sudo tee -a /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties > /dev/null
			fi
			sudo runuser -l ${kafka_user} -c 'mkdir -p ${zookeeper_data_dir}'
			zookeeper_data_dir_esc=\$(eval echo ${zookeeper_data_dir} | sed 's/\//\\\\\//g')
			sudo sed -i "s/^dataDir=.*/dataDir=\${zookeeper_data_dir_esc}/g" /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties
			echo ${nodeid} | sudo runuser -l ${kafka_user} -c 'tee ${zookeeper_data_dir}/myid > /dev/null'
		EOF
		)"
		remote="${installer}@$(get all ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "hardening the kafka user account..."
for host in ${nodes[@]}; do
	hostid=$(get node-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${hostid} <= 3 )); then
		command="$(cat <<-EOF
			sudo deluser ${kafka_user} sudo
			which passwd &> /dev/null || sudo apt-get install -y passwd
			sudo passwd ${kafka_user} -l
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "creating a system unit file for zookeeper..."
for host in ${nodes[@]}; do
	hostid=$(get node-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${hostid} <= 3 )); then
		command="$(cat <<-EOF
			if [ -f "/etc/systemd/system/zookeeper.service" ]; then 
				sudo rm /etc/systemd/system/zookeeper.service
			fi
			echo "[Unit]" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "Requires=network.target remote-fs.target" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "After=network.target remote-fs.target" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "[Service]" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "Type=simple" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "User=${kafka_user}" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "ExecStart=/bin/sh -c '/home/${kafka_user}/kafka_${kafka_version}/bin/zookeeper-server-start.sh /home/${kafka_user}/kafka_${kafka_version}/config/zookeeper.properties > ${kafka_log_dir}/zookeeper.log 2>&1'" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "ExecStop=/home/${kafka_user}/kafka_${kafka_version}/bin/zookeeper-server-stop.sh" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "Restart=on-abnormal" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "[Install]" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "WantedBy=multi-user.target" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
			echo "" | sudo tee -a /etc/systemd/system/zookeeper.service > /dev/null
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "creating a system unit file for kafka..."
for host in ${nodes[@]}; do
	hostid=$(get node-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${hostid} <= 3 )); then
		command="$(cat <<-EOF
			if [ -f "/etc/systemd/system/kafka.service" ]; then
				sudo rm /etc/systemd/system/kafka.service
			fi
			echo "[Unit]" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "Requires=zookeeper.service" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "After=zookeeper.service" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "[Service]" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "Type=simple" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "User=${kafka_user}" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "ExecStart=/bin/sh -c '/home/${kafka_user}/kafka_${kafka_version}/bin/kafka-server-start.sh /home/${kafka_user}/kafka_${kafka_version}/config/server.properties > ${kafka_log_dir}/kafka.log 2>&1'" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "ExecStop=/home/${kafka_user}/kafka_${kafka_version}/bin/kafka-server-stop.sh" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "Restart=on-abnormal" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "[Install]" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "WantedBy=multi-user.target" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
			echo "" | sudo tee -a /etc/systemd/system/kafka.service > /dev/null
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "starting kafka/zookeeper and enabling the managed services..."
for host in ${nodes[@]}; do
	hostid=$(get node-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${hostid} <= 3 )); then
		command="$(cat <<-EOF
			sudo systemctl daemon-reload
			sudo systemctl enable zookeeper
			sudo systemctl enable kafka
			sudo systemctl start zookeeper
			sudo systemctl start kafka
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done
for host in ${exists[@]}; do
	hostid=$(get existing-id ${host})
	if [[ ${host} != ${registry_host} ]] && (( ${hostid} <= 3 )); then
		command="$(cat <<-EOF
			sudo systemctl restart zookeeper
			sudo systemctl restart kafka
		EOF
		)"
		remote="${installer}@$(get exists ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "creating user for nifi installation..."
for host in ${nodes[@]}; do
	command="$(cat <<-EOF
		## create a separate user for nifi
		\$(grep -q "^${username}" "/etc/passwd" > /dev/null)
		if [ \$? -ne 0 ]; then
			pass=\$(perl -e 'print crypt(\$ARGV[0], "password")' ${password})
			sudo useradd -m -p "\${pass}" "${username}"
			[ \$? -eq 0 ] && echo "${username} user has been added to system!" || echo "Failed to add ${username} user!"
			sudo adduser ${username} sudo
		fi
	EOF
	)"
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "installing nifi components..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			which unzip &> /dev/null || sudo apt-get install -y unzip\

			## download and extract the nifi package
			if [ ! -d "${installation_folder}nifi-${nifi_version}/" ]; then
				echo "installing nifi binaries for version ${nifi_version}..."
				if [ ! -f "${installation_folder}nifi-${nifi_version}-bin.zip" ]; then
					sudo wget -P ${installation_folder} ${dist}/nifi/${nifi_version}/nifi-${nifi_version}-bin.zip
					sudo chown ${username}: ${installation_folder}nifi-${nifi_version}-bin.zip
				fi
				sudo unzip ${installation_folder}nifi-${nifi_version}-bin.zip -d ${installation_folder}
				sudo chown -R ${username}: ${installation_folder}nifi-${nifi_version}/
			fi

			## and create a symlink for /usr/bin/nifi
			echo "creating symlink to ${installation_folder}nifi-${nifi_version}/bin/nifi.sh..."
			if [ -L "/usr/bin/nifi" ]; then
				sudo rm /usr/bin/nifi
			fi
			sudo ln -s ${installation_folder}nifi-${nifi_version}/bin/nifi.sh /usr/bin/nifi

			## set nifi home and escape the forward slashes in the path before storing in the environment
			nifi_home="${installation_folder}nifi-${nifi_version}/"
			nifi_home_esc=\$(eval echo \${nifi_home} | sed 's/\//\\\\\//g')
			\$(grep -q ^NIFI_HOME= /etc/environment)
			if [ \$? -eq 0 ]; then
				## if the environment points to another nifi home then replace it with the latest
				echo "updating nifi home in the environment..."
				sudo sed -i "s/^NIFI_HOME=.*/NIFI_HOME=\${nifi_home_esc}/g" /etc/environment
			else
				## otherwise add nifi home to the environment
				echo "adding nifi home to the environment..."
				## make sure we have a new line in our file
				file=/etc/environment
				if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
					echo "new line at end of \${file}!"
				else
					echo "" | sudo tee -a \${file} > /dev/null
				fi
				echo NIFI_HOME=\${nifi_home} | sudo tee -a /etc/environment > /dev/null
			fi
			
			## and reload the nifi home environment variables
			. /etc/environment
			echo "NIFI_HOME=\${NIFI_HOME}"
		EOF
		)"
	fi
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "installing nifi toolkit..."
for host in ${nodes[@]}; do
	command="$(cat <<-EOF
		which wget &> /dev/null || sudo apt-get install -y wget
		which unzip &> /dev/null || sudo apt-get install -y unzip

		## download and extract the nifi toolkit package
		if [ ! -d "${installation_folder}nifi-toolkit-${nifi_version}/" ]; then
			echo "installing nifi toolkit binaries for version ${nifi_version}..."
			if [ ! -f "${installation_folder}nifi-toolkit-${nifi_version}-bin.zip" ]; then
				sudo wget -P ${installation_folder} ${dist}/nifi/${nifi_version}/nifi-toolkit-${nifi_version}-bin.zip
				sudo chown ${username}: ${installation_folder}nifi-toolkit-${nifi_version}-bin.zip
			fi
			sudo unzip ${installation_folder}/nifi-toolkit-${nifi_version}-bin.zip -d ${installation_folder}
			sudo chown -R ${username}: ${installation_folder}nifi-toolkit-${nifi_version}/
		fi

		## set nifi toolkit home and escape the forward slashes in the path before storing in the environment
		nifi_toolkit_home="${installation_folder}nifi-toolkit-${nifi_version}/"
		nifi_toolkit_home_esc=\$(eval echo \${nifi_toolkit_home} | sed 's/\//\\\\\//g')
		\$(grep -q ^NIFI_TOOLKIT_HOME= /etc/environment)
		if [ \$? -eq 0 ]; then
			## if the environment points to another nifi toolkit home then replace it with the latest
			echo "updating nifi toolkit home in the environment..."
			sudo sed -i "s/^NIFI_TOOLKIT_HOME=.*/NIFI_TOOLKIT_HOME=\${nifi_toolkit_home_esc}/g" /etc/environment
		else
			## otherwise add nifi toolkit home to the environment
			echo "adding nifi toolkit home to the environment..."
			## make sure we have a new line in our file
			file=/etc/environment
			if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
				echo "new line at end of \${file}!"
			else
				echo "" | sudo tee -a \${file} > /dev/null
			fi
			echo NIFI_TOOLKIT_HOME=\${nifi_toolkit_home} | sudo tee -a /etc/environment > /dev/null
		fi
		
		## and reload the nifi toolkit home environment variables
		. /etc/environment
		echo "NIFI_TOOLKIT_HOME=\${NIFI_TOOLKIT_HOME}"
	EOF
	)"
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "hardening the nifi user account..."
for host in ${nodes[@]}; do
	command="$(cat <<-EOF
		sudo deluser ${username} sudo
		which passwd &> /dev/null || sudo apt-get install -y passwd
		sudo passwd ${username} -l
	EOF
	)"
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "overwriting certificates for the nifi cluster to include the new nodes..."
nodestr=""
clientdn=""
for node in ${all[@]}; do
	nodeip=$(get all ${node})
	nodestr+="${nodeip},"
	clientdn+="--clientCertDn \"CN=${nodeip}, OU=NIFI\" "
done
remote="${installer}@${authority}"
keystorePasswd=$(echo $(sed -n "/nifi.security.keystorePasswd=/p" ~/tls/${authority}/nifi.properties) | cut -f2 -d=)
keyPasswd=$(echo $(sed -n "/nifi.security.keyPasswd=/p" ~/tls/${authority}/nifi.properties) | cut -f2 -d=)
trustStorePassword=$(echo $(sed -n "/nifi.security.truststorePasswd=/p" ~/tls/${authority}/nifi.properties) | cut -f2 -d=)
command="$(cat <<-EOF
	sudo \${NIFI_TOOLKIT_HOME}bin/tls-toolkit.sh standalone \
		--hostnames "${nodestr::-1}" \
		--certificateAuthorityHostname "${authority}" \
		--clientCertDn "CN=${username}, OU=NIFI" \
		${clientdn::-1} \
		--subjectAlternativeNames "${nodestr::-1}" \
		--keyStorePassword "${keystorePasswd}" \
		--keyPassword "${keyPasswd}" \
		--trustStorePassword "${trustStorePassword}" \
		--isOverwrite --outputDirectory ~/tls
	sudo chown -R ${installer}: ~/tls/
EOF
)"
echo "ssh -t ${remote} \"${command}\""
ssh -t ${remote} "${command}"
rm -rf ~/tls
echo "scp -r ${remote}:~/tls ~/tls"
scp -r ${remote}:~/tls ~/tls
for host in ${all[@]}; do
	hostip=$(get all ${host})
	if [[ ${hostip} != ${authority} ]]; then
		remote="${installer}@${hostip}"
		command="rm -rf ~/tls; mkdir -p ~/tls"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
		echo "scp -r ~/tls/${hostip} ${remote}:~/tls/${hostip}"
		scp -r ~/tls/${hostip} ${remote}:~/tls/${hostip}
	fi
done

echo "updating nifi configuration with details needed for a clustered node installation..."
for host in ${all[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			sudo sed -i "s/^nifi.state.management.embedded.zookeeper.start=.*/nifi.state.management.embedded.zookeeper.start=false/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.zookeeper.connect.string=.*/nifi.zookeeper.connect.string=${zkconnstr::-1}/g" \${NIFI_HOME}conf/nifi.properties
			which xmlstarlet &> /dev/null || sudo apt-get install -y xmlstarlet
			sudo xmlstarlet ed -P -L -u /stateManagement/cluster-provider/property[@name='"Connect String"'] -v "${zkconnstr::-1}" \${NIFI_HOME}conf/state-management.xml
		EOF
		)"
		remote="${installer}@$(get all ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		hostip=$(get node ${host})
		command="$(cat <<-EOF
			## then update the nifi cluster node details
			sudo sed -i "s/^nifi.cluster.protocol.is.secure=.*/nifi.cluster.protocol.is.secure=${secure}/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.is.node=.*/nifi.cluster.is.node=true/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.node.address=.*/nifi.cluster.node.address=${hostip}/g" \${NIFI_HOME}conf/nifi.properties
			if [ ${secure} = true ]; then
				sudo sed -i "s/^nifi.cluster.node.protocol.port=.*/nifi.cluster.node.protocol.port=11443/g" \${NIFI_HOME}conf/nifi.properties
			else
				sudo sed -i "s/^nifi.cluster.node.protocol.port=.*/nifi.cluster.node.protocol.port=9997/g" \${NIFI_HOME}conf/nifi.properties
			fi
			\$(grep -q "^nifi.cluster.node.protocol.threads=" "\${NIFI_HOME}conf/nifi.properties")
			if [ \$? -eq 0 ]; then
				## if the property already exists then update the property value
				sudo sed -i "s/^nifi.cluster.node.protocol.threads=.*/nifi.cluster.node.protocol.threads=50/g" \${NIFI_HOME}conf/nifi.properties
			else
				## otherwise add the property to the nifi properties file
				echo "nifi.cluster.node.protocol.threads=50" | sudo tee -a \${NIFI_HOME}conf/nifi.properties > /dev/null 
			fi
			sudo sed -i "s/^nifi.cluster.node.protocol.max.threads=.*/nifi.cluster.node.protocol.max.threads=50/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.node.event.history.size=.*/nifi.cluster.node.event.history.size=25/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.node.connection.timeout=.*/nifi.cluster.node.connection.timeout=30 sec/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.node.read.timeout=.*/nifi.cluster.node.read.timeout=30 sec/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.node.max.concurrent.requests=.*/nifi.cluster.node.max.concurrent.requests=100/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.firewall.file=.*/nifi.cluster.firewall.file=/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.load.balance.host=.*/nifi.cluster.load.balance.host=${hostip}/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.load.balance.connections.per.node=.*/nifi.cluster.load.balance.connections.per.node=4/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.load.balance.max.thread.count=.*/nifi.cluster.load.balance.max.thread.count=12/g" \${NIFI_HOME}conf/nifi.properties

			## and update the nifi remote mode properties
			sudo sed -i "s/^nifi.remote.input.host=.*/nifi.remote.input.host=${hostip}/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.remote.input.secure=.*/nifi.remote.input.secure=${secure}/g" \${NIFI_HOME}conf/nifi.properties
			if [ ${secure} = true ]; then
				sudo sed -i "s/^nifi.remote.input.socket.port=.*/nifi.remote.input.socket.port=10443/g" \${NIFI_HOME}conf/nifi.properties
			else
				sudo sed -i "s/^nifi.remote.input.socket.port=.*/nifi.remote.input.socket.port=9998/g" \${NIFI_HOME}conf/nifi.properties
			fi
			sudo sed -i "s/^nifi.remote.input.http.enabled=.*/nifi.remote.input.http.enabled=true/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.remote.input.http.transaction.ttl=.*/nifi.remote.input.http.transaction.ttl=30 sec/g" \${NIFI_HOME}conf/nifi.properties

			## update http properties and the required sensitive property key value
			if [ ${secure} = true ]; then
				sudo sed -i "s/^nifi.web.http.host=.*/nifi.web.http.host=/g" \${NIFI_HOME}conf/nifi.properties
				sudo sed -i "s/^nifi.web.http.port=.*/nifi.web.http.port=/g" \${NIFI_HOME}conf/nifi.properties
				sudo sed -i "s/^nifi.web.https.host=.*/nifi.web.https.host=${hostip}/g" \${NIFI_HOME}conf/nifi.properties
				sudo sed -i "s/^nifi.web.https.port=.*/nifi.web.https.port=9443/g" \${NIFI_HOME}conf/nifi.properties
			else
				sudo sed -i "s/^nifi.web.http.host=.*/nifi.web.http.host=${hostip}/g" \${NIFI_HOME}conf/nifi.properties
				sudo sed -i "s/^nifi.web.http.port=.*/nifi.web.http.port=8080/g" \${NIFI_HOME}conf/nifi.properties
				sudo sed -i "s/^nifi.web.https.host=.*/nifi.web.https.host=/g" \${NIFI_HOME}conf/nifi.properties
				sudo sed -i "s/^nifi.web.https.port=.*/nifi.web.https.port=/g" \${NIFI_HOME}conf/nifi.properties
			fi
			sensitive_prop_key_esc=\$(eval echo ${sensitive_prop_key} | sed 's/\//\\\\\//g')
			sudo sed -i "s/^nifi.sensitive.props.key=.*/nifi.sensitive.props.key=\${sensitive_prop_key_esc}/g" \${NIFI_HOME}conf/nifi.properties

			## then update a few additional properties that should help improve performance of the node
			sudo sed -i "s/^nifi.bored.yield.duration=.*/nifi.bored.yield.duration=100 millis/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.flow.election.max.wait.time=.*/nifi.cluster.flow.election.max.wait.time=1 min/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.cluster.flow.election.max.candidates=.*/nifi.cluster.flow.election.max.candidates=3/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.queue.swap.threshold=.*/nifi.queue.swap.threshold=50000/g" \${NIFI_HOME}conf/nifi.properties
		EOF
		)"
	fi
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "updating nifi filesystem and mount point configuration needed for the installation..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			## update the default and custom mount point repository location properties
			sudo mkdir -p ${flowfile_repo}
			sudo chown ${username}:${username} ${flowfile_repo}
			flowfile_repo_esc=\$(eval echo ${flowfile_repo} | sed 's/\//\\\\\//g')
			sudo sed -i "s/^nifi.flowfile.repository.directory=.*/nifi.flowfile.repository.directory=\${flowfile_repo_esc}/g" \${NIFI_HOME}conf/nifi.properties
			sudo mkdir -p ${database_repo}
			sudo chown ${username}:${username} ${database_repo}
			database_repo_esc=\$(eval echo ${database_repo} | sed 's/\//\\\\\//g')
			sudo sed -i "s/^nifi.database.directory=.*/nifi.database.directory=\${database_repo_esc}/g" \${NIFI_HOME}conf/nifi.properties
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		prev="nifi.content.repository.directory.default="
		command="$(cat <<-EOF
			## make sure we have a new line at the end of our files before we append anything
			file=/etc/fstab
			if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
				echo "new line at end of \${file}!"
			else
				echo "" | sudo tee -a \${file} > /dev/null
			fi

			## coment out the default content repository if not provided
			if [[ -z "${content_repo}" ]]; then
				\$(grep -q "^${prev}" "\${NIFI_HOME}conf/nifi.properties")
				if [ \$? -eq 0 ]; then
					sudo sed -i "s/^${prev}.*/#${prev}/g" \${NIFI_HOME}conf/nifi.properties
				fi
			## otherwise uncomment and/or update the default content repository
			else
				sudo mkdir -p ${content_repo}
				sudo chown ${username}:${username} ${content_repo}
				content_repo_esc=\$(eval echo ${content_repo} | sed 's/\//\\\\\//g')
				\$(grep -q "^${prev}" "\${NIFI_HOME}conf/nifi.properties")
				if [ \$? -eq 0 ]; then
					sudo sed -i "s/^${prev}.*/${prev}\${content_repo_esc}/g" \${NIFI_HOME}conf/nifi.properties
				else
					\$(grep -q "^#${prev}" "\${NIFI_HOME}conf/nifi.properties")
					if [ \$? -eq 0 ]; then
						sudo sed -i "s/^#${prev}.*/${prev}\${content_repo_esc}/g" \${NIFI_HOME}conf/nifi.properties
					fi
				fi
			fi
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
		
		## if content repository not provided then the default repository should be commented out
		if [[ -z "${content_repo}" ]]; then
			prev="#${prev}"
		fi
		## for each content repo filesystem add the mount point to the configuration file
		for mnt in ${contrepos[@]}; do
			next="nifi.content.repository.directory.$(get "contrepo-id" $mnt)="
			fs=$(get "contrepo" $mnt)
			command="$(cat <<-EOF
				## insert additional mounts in configuration if the mapping does not already exist
				\$(grep -q "^${next}" "\${NIFI_HOME}conf/nifi.properties")
				if [ \$? -ne 0 ]; then
					sudo sed -i "/^${prev}.*/a\\${next}\/mnt\/${mnt}" \${NIFI_HOME}conf/nifi.properties
				## and replace the value if it does exist
				else
					sudo sed -i "s/^${next}.*/${next}\/mnt\/${mnt}/g" \${NIFI_HOME}conf/nifi.properties
				fi
			EOF
			)"
			remote="${installer}@$(get node ${host})"
			echo "ssh -t ${remote} \"${command}\""
			ssh -t ${remote} "${command}"
			prev=$next
			
			command="$(cat <<-EOF
				## format and mount the filesystem if it has not been done already
				if [ ! -d "/mnt/${mnt}/" ]; then
					sudo mkdir -p /mnt/${mnt}
					sudo mkfs.ext4 ${fs}
					#sudo e4label ${fs} ${mnt}
					sudo mount ${fs} //mnt/${mnt}
					sudo chown -R ${username}:${username} /mnt/${mnt}
				fi
				
				## add the mount to /etc/fstab configuration, if the filesystem exists then replace, otherwise append
				\$(grep -q "^${fs}" "/etc/fstab")
				if [ \$? -eq 0 ]; then
					fs_esc=\$(eval echo ${fs} | sed 's/\//\\\\\//g')
					sudo sed -i "s/^\${fs_esc}.*/\${fs_esc}	 \/mnt\/${mnt}	 ext4	 defaults	 0	 2/g" /etc/fstab
				else
					echo ${fs}	 /mnt/${mnt}	 ext4	 defaults	 0	 2 | sudo tee -a /etc/fstab > /dev/null
				fi
			EOF
			)"
			remote="${installer}@$(get node ${host})"
			echo "ssh -t ${remote} \"${command}\""
			ssh -t ${remote} "${command}"
		done
	fi
done

for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		prev="nifi.provenance.repository.directory.default="
		command="$(cat <<-EOF
			## make sure we have a new line at the end of our files before we append anything
			file=/etc/fstab
			if [[ -s \${file} && -z "\$(tail -c 1 \${file})" ]]; then
				echo "new line at end of \${file}!"
			else
				echo "" | sudo tee -a \${file} > /dev/null
			fi

			## coment out the default provenance repository if not provided
			if [[ -z "${provenance_repo}" ]]; then
				\$(grep -q "^${prev}" "\${NIFI_HOME}conf/nifi.properties")
				if [ \$? -eq 0 ]; then
					sudo sed -i "s/^${prev}.*/#${prev}/g" \${NIFI_HOME}conf/nifi.properties
				fi
			## otherwise uncomment and/or update the default provenance repository
			else
				sudo mkdir -p ${provenance_repo}
				sudo chown ${username}:${username} ${provenance_repo}
				provenance_repo_esc=\$(eval echo ${provenance_repo} | sed 's/\//\\\\\//g')
				\$(grep -q "^${prev}" "\${NIFI_HOME}conf/nifi.properties")
				if [ \$? -eq 0 ]; then
					sudo sed -i "s/^${prev}.*/${prev}\${provenance_repo_esc}/g" \${NIFI_HOME}conf/nifi.properties
				else
					\$(grep -q "^#${prev}" "\${NIFI_HOME}conf/nifi.properties")
					if [ \$? -eq 0 ]; then
						sudo sed -i "s/^#${prev}.*/${prev}\${provenance_repo_esc}/g" \${NIFI_HOME}conf/nifi.properties
					fi
				fi
			fi
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
		
		## if provenance repository not provided hhen the default repository should be commented out
		if [[ -z "${provenance_repo}" ]]; then
			prev="#${prev}"
		fi
		## for each provenance repo filesystem add the mount point to the configuration file
		for mnt in ${provrepos[@]}; do
			next="nifi.provenance.repository.directory.$(get "provrepo-id" $mnt)="
			fs=$(get "provrepo" $mnt)
			command="$(cat <<-EOF
				## insert additional mounts in configuration if the mapping does not already exist
				\$(grep -q "^${next}" "\${NIFI_HOME}conf/nifi.properties")
				if [ \$? -ne 0 ]; then
					sudo sed -i "/^${prev}.*/a\\${next}\/mnt\/${mnt}" \${NIFI_HOME}conf/nifi.properties
				## and replace the value if it does exist
				else
					sudo sed -i "s/^${next}.*/${next}\/mnt\/${mnt}/g" \${NIFI_HOME}conf/nifi.properties
				fi
			EOF
			)"
			remote="${installer}@$(get node ${host})"
			echo "ssh -t ${remote} \"${command}\""
			ssh -t ${remote} "${command}"
			prev=$next
			
			command="$(cat <<-EOF
				## format and mount the filesystem if it has not been done already
				if [ ! -d "/mnt/${mnt}/" ]; then
					sudo mkdir -p /mnt/${mnt}
					sudo mkfs.ext4 ${fs}
					#sudo e4label ${fs} ${mnt}
					sudo mount ${fs} //mnt/${mnt}
					sudo chown -R ${username}:${username} /mnt/${mnt}
				fi
				
				## add the mount to /etc/fstab configuration, if the filesystem exists then replace, otherwise append
				\$(grep -q "^${fs}" "/etc/fstab")
				if [ \$? -eq 0 ]; then
					fs_esc=\$(eval echo ${fs} | sed 's/\//\\\\\//g')
					sudo sed -i "s/^\${fs_esc}.*/\${fs_esc}	 \/mnt\/${mnt}	 ext4	 defaults	 0	 2/g" /etc/fstab
				else
					echo ${fs}	 /mnt/${mnt}	 ext4	 defaults	 0	 2 | sudo tee -a /etc/fstab > /dev/null
				fi
			EOF
			)"
			remote="${installer}@$(get node ${host})"
			echo "ssh -t ${remote} \"${command}\""
			ssh -t ${remote} "${command}"
		done
	fi
done

echo "updating nifi security properties for certificates, key and trust stores needed for the installation..."
for host in ${all[@]}; do
	hostip=$(get all ${host})
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			## read from the properties file generated by the nifi toolkit and update the installation properties file...
			sudo sed -i "s/^nifi.security.keystore=.*/nifi.security.keystore=\$(eval echo  \"\${NIFI_HOME}conf/keystore.jks\" | sed 's/\//\\\\\//g')/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.security.keystoreType=.*/nifi.security.keystoreType=jks/g" \${NIFI_HOME}conf/nifi.properties
			value=\$(sed -n "/nifi.security.keystorePasswd=/p" ~/tls/${hostip}/nifi.properties)
			\$(grep -q "^nifi.security.keystorePasswd=" "\${NIFI_HOME}conf/nifi.properties")
			if [ \$? -eq 0 ]; then
				## if the password already exists then replace it with a new value
				sudo sed -i "s/^nifi.security.keystorePasswd=.*/\$(eval echo \${value} | sed 's/\//\\\\\//g')/g" \${NIFI_HOME}conf/nifi.properties
			else
				## otherwise add the password to the nifi properties file
				echo "\${value}" | sudo tee -a \${NIFI_HOME}conf/nifi.properties > /dev/null
			fi
			value=\$(sed -n "/nifi.security.keyPasswd=/p" ~/tls/${hostip}/nifi.properties)
			\$(grep -q "^nifi.security.keyPasswd=" "\${NIFI_HOME}conf/nifi.properties")
			if [ \$? -eq 0 ]; then
				## if the password already exists then replace it with a new value
				sudo sed -i "s/^nifi.security.keyPasswd=.*/\$(eval echo \${value} | sed 's/\//\\\\\//g')/g" \${NIFI_HOME}conf/nifi.properties
			else
				## otherwise add the password to the nifi properties file
				echo "\${value}" | sudo tee -a \${NIFI_HOME}conf/nifi.properties > /dev/null
			fi
			sudo sed -i "s/^nifi.security.truststore=.*/nifi.security.truststore=\$(eval echo \${NIFI_HOME}conf/truststore.jks | sed 's/\//\\\\\//g')/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.security.truststoreType=.*/nifi.security.truststoreType=jks/g" \${NIFI_HOME}conf/nifi.properties
			value=\$(sed -n "/nifi.security.truststorePasswd=/p" ~/tls/${hostip}/nifi.properties)
			\$(grep -q "^nifi.security.truststorePasswd=" "\${NIFI_HOME}conf/nifi.properties")
			if [ \$? -eq 0 ]; then
				## if the password already exists then replace it with a new value
				sudo sed -i "s/^nifi.security.truststorePasswd=.*/\$(eval echo \${value} | sed 's/\//\\\\\//g')/g" \${NIFI_HOME}conf/nifi.properties
			else
				## otherwise add the password to the nifi properties file
				echo "\${value}" | sudo tee -a \${NIFI_HOME}conf/nifi.properties > /dev/null
			fi

			## copy the keystore and truststore into the nifi conf directory and restrict permissions on the files
			sudo cp ~/tls/${hostip}/*.jks \${NIFI_HOME}conf/.
			sudo chown ${username}:${username} \${NIFI_HOME}conf/*.jks
			sudo chmod 600 \${NIFI_HOME}conf/*.jks
		EOF
		)"
	else
		command="$(cat <<-EOF
			## read from the properties file generated by the nifi toolkit and update the installation properties file...
			sudo sed -i "s/^nifi.registry.security.keystore=.*/nifi.registry.security.keystore=\$(eval echo  \"\${NIFI_REGISTRY_HOME}conf/keystore.jks\" | sed 's/\//\\\\\//g')/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			sudo sed -i "s/^nifi.registry.security.keystoreType=.*/nifi.registry.security.keystoreType=jks/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			value=\$(sed -n "/nifi.security.keystorePasswd=/p" ~/tls/${hostip}/nifi.properties)
			\$(grep -q "^nifi.registry.security.keystorePasswd=" "\${NIFI_REGISTRY_HOME}conf/nifi-registry.properties")
			if [ \$? -eq 0 ]; then
				## if the password already exists then replace it with a new value
				sudo sed -i "s/^nifi.registry.security.keystorePasswd=.*/\$(eval echo \${value} | sed 's/\//\\\\\//g')/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			else
				## otherwise add the password to the nifi properties file
				echo "\${value}" | sudo tee -a \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties > /dev/null
			fi
			value=\$(sed -n "/nifi.security.keyPasswd=/p" ~/tls/${hostip}/nifi.properties)
			\$(grep -q "^nifi.registry.security.keyPasswd=" "\${NIFI_REGISTRY_HOME}conf/nifi-registry.properties")
			if [ \$? -eq 0 ]; then
				## if the password already exists then replace it with a new value
				sudo sed -i "s/^nifi.registry.security.keyPasswd=.*/\$(eval echo \${value} | sed 's/\//\\\\\//g')/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			else
				## otherwise add the password to the nifi properties file
				echo "\${value}" | sudo tee -a \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties > /dev/null
			fi
			sudo sed -i "s/^nifi.registry.security.truststore=.*/nifi.registry.security.truststore=\$(eval echo \${NIFI_REGISTRY_HOME}conf/truststore.jks | sed 's/\//\\\\\//g')/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			sudo sed -i "s/^nifi.registry.security.truststoreType=.*/nifi.registry.security.truststoreType=jks/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			value=\$(sed -n "/nifi.security.truststorePasswd=/p" ~/tls/${hostip}/nifi.properties)
			\$(grep -q "^nifi.registry.security.truststorePasswd=" "\${NIFI_REGISTRY_HOME}conf/nifi-registry.properties")
			if [ \$? -eq 0 ]; then
				## if the password already exists then replace it with a new value
				sudo sed -i "s/^nifi.registry.security.truststorePasswd=.*/\$(eval echo \${value} | sed 's/\//\\\\\//g')/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties
			else
				## otherwise add the password to the nifi properties file
				echo "\${value}" | sudo tee -a \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties > /dev/null
			fi
			
			## insert registry back into the key names for the tls security properties that were replaced
			sudo sed -i "s/^nifi.security/nifi.registry.security/g" \${NIFI_REGISTRY_HOME}conf/nifi-registry.properties

			## copy the keystore and truststore into the nifi conf directory and restrict permissions on the files
			sudo cp ~/tls/${hostip}/*.jks \${NIFI_REGISTRY_HOME}conf/.
			sudo chown ${username}:${username} \${NIFI_REGISTRY_HOME}conf/*.jks
			sudo chmod 600 \${NIFI_REGISTRY_HOME}conf/*.jks
		EOF
		)"
	fi
	remote="${installer}@$(get all ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

if [ ${secure} = true ]; then
	## update the xml properties of the authorizers file to include the identities of each node
	for host in ${all[@]}; do
		remote="${installer}@$(get all ${host})"
		command="$(cat <<-EOF
			which xmlstarlet &> /dev/null || sudo apt-get install -y xmlstarlet
		EOF
		)"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
		
		xmlcmd="xmlstarlet ed -P -L -u /authorizers/userGroupProvider/property[@name='\"Initial User Identity 1\"'] -v \"CN=${username}, OU=NIFI\""
		for node in ${all[@]}; do
			nodeid=$(get all-id ${node})
			if ! [[ ${nodeid} =~ ^[0-9]+$ ]] ; then
				echo "ERROR: Node ID ${nodeid} for ${node} is not an integer"
				exit 1
			fi
			nodeid=$((${nodeid} + 2))
			xmlcmd+=" -d /authorizers/userGroupProvider/property[@name='\"Initial User Identity ${nodeid}\"'] -s /authorizers/userGroupProvider -t elem -n propertyTMP -v \"CN=$(get all ${node}), OU=NIFI\" -i //propertyTMP -t attr -n name -v \"Initial User Identity ${nodeid}\" -r //propertyTMP -v property"
		done
		if [[ ${host} != ${registry_host} ]]; then
			xmlcmd+=" \${NIFI_HOME}conf/authorizers.xml"
		else
			xmlcmd+=" \${NIFI_REGISTRY_HOME}conf/authorizers.xml"
		fi
		command="$(cat <<-EOF
			sudo $xmlcmd
		EOF
		)"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
		
		xmlcmd="xmlstarlet ed -P -L -u /authorizers/accessPolicyProvider/property[@name='\"Initial Admin Identity\"'] -v \"CN=${username}, OU=NIFI\""
		for node in ${all[@]}; do
			nodeid=$(get all-id ${node})
			xmlcmd+=" -d /authorizers/accessPolicyProvider/property[@name='\"Node Identity ${nodeid}\"'] -s /authorizers/accessPolicyProvider -t elem -n propertyTMP -v \"CN=$(get all ${node}), OU=NIFI\" -i //propertyTMP -t attr -n name -v \"Node Identity ${nodeid}\" -r //propertyTMP -v property"
		done
		if [[ ${host} != ${registry_host} ]]; then
			xmlcmd+=" \${NIFI_HOME}conf/authorizers.xml"
		else
			xmlcmd+=" \${NIFI_REGISTRY_HOME}conf/authorizers.xml"
		fi
		command="$(cat <<-EOF
			sudo $xmlcmd
		EOF
		)"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	done
fi

echo "updating nifi memory configurations for this installation..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			## setting the min and max memory allocations in the bootstrap configuration
			sudo sed -i "s/^java.arg.2=.*/java.arg.2=-Xms${memory}/g" \${NIFI_HOME}conf/bootstrap.conf
			sudo sed -i "s/^java.arg.3=.*/java.arg.3=-Xmx${memory}/g" \${NIFI_HOME}conf/bootstrap.conf
			## make sure the UseG1GC java option is commented out due to a known bug in its implementation
			\$(grep -q "^java.arg.13=" "\${NIFI_HOME}conf/bootstrap.conf")
			if [ \$? -ne 0 ]; then
				sudo sed -i "s/^java.arg.13=.*/#java.arg.13=-XX:+UseG1GC/g" \${NIFI_HOME}conf/bootstrap.conf
			fi
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "updating the configuration to change the log file location and rollover policies for nifi..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			sudo mkdir -p ${log_dir}
			sudo chown ${username}:${username} ${log_dir}
			log_dir_esc=$(eval echo ${log_dir} | sed 's/\//\\\\\//g')
			sudo sed -i "s/^NIFI_LOG_DIR=.*/NIFI_LOG_DIR=\"\\\$\(setOrDefault \"\\\$NIFI_LOG_DIR\" \"\${log_dir_esc}\"\)\"/g" \${NIFI_HOME}bin/nifi-env.sh
			
			which xmlstarlet &> /dev/null || sudo apt-get install -y xmlstarlet
			sudo xmlstarlet ed -P -L -u /configuration/appender[@name='"APP_FILE"']/rollingPolicy/maxHistory -v 720 \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -a /configuration/appender[@name='"APP_FILE"']/rollingPolicy/maxHistory -t elem -n totalSizeCap -v "512MB" \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -u /configuration/appender[@name='"USER_FILE"']/rollingPolicy/maxHistory -v 30 \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -a /configuration/appender[@name='"USER_FILE"']/rollingPolicy/maxHistory -t elem -n totalSizeCap -v "128MB" \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -u /configuration/appender[@name='"REQUEST_FILE"']/rollingPolicy/maxHistory -v 30 \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -a /configuration/appender[@name='"REQUEST_FILE"']/rollingPolicy/maxHistory -t elem -n totalSizeCap -v "128MB" \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -u /configuration/appender[@name='"BOOTSTRAP_FILE"']/rollingPolicy/maxHistory -v 30 \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -a /configuration/appender[@name='"BOOTSTRAP_FILE"']/rollingPolicy/maxHistory -t elem -n totalSizeCap -v "128MB" \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -u /configuration/appender[@name='"DEPRECATION_FILE"']/rollingPolicy/maxHistory -v 30 \${NIFI_HOME}conf/logback.xml
			sudo xmlstarlet ed -P -L -u /configuration/appender[@name='"DEPRECATION_FILE"']/rollingPolicy/totalSizeCap -v "128MB" \${NIFI_HOME}conf/logback.xml
		EOF
		)"
	fi
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "updating configurations for IO intensive operations on Linux..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			sudo sed -i '/^# End of file/d' /etc/security/limits.conf
			sudo sed -i '/^\*       hard    nofile  /{h;s/nofile    .*/nofile       50000/};\${x;/^\$/{s//\*       hard    nofile  50000/;H};x}' /etc/security/limits.conf
			sudo sed -i '/^\*       soft    nofile  /{h;s/nofile    .*/nofile       50000/};\${x;/^\$/{s//\*       soft    nofile  50000/;H};x}' /etc/security/limits.conf
			sudo sed -i '/^\*       hard    nproc   /{h;s/nproc     .*/nproc        10000/};\${x;/^\$/{s//\*       hard    nproc   10000/;H};x}' /etc/security/limits.conf
			sudo sed -i '/^\*       soft    nproc   /{h;s/nproc     .*/nproc        10000/};\${x;/^\$/{s//\*       soft    nproc   10000/;H};x}' /etc/security/limits.conf
			echo "# End of file" | sudo tee -a /etc/security/limits.conf > /dev/null
			sudo sysctl -w net.ipv4.ip_local_port_range="10000 65000"
			sudo sysctl -w net.ipv4.netfilter.ip_conntrack_tcp_timeout_time_wait="1"
			sudo sed -i '/^vm.swappiness =/{h;s/=.*/= 0/};\${x;/^\$/{s//vm.swappiness = 0/;H};x}' /etc/sysctl.conf
			. /etc/environment
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "updating nifi configuration files to point from the current working directory to NIFI_HOME"
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			nifi_home_esc=\$(eval echo \${NIFI_HOME} | sed 's/\//\\\\\//g')
			sudo sed -i "s/=\.\//=\${nifi_home_esc}/g" \${NIFI_HOME}conf/zookeeper.properties
			sudo sed -i "s/=\.\//=\${nifi_home_esc}/g" \${NIFI_HOME}conf/stateless.properties
			sudo sed -i "s/\.\//\${nifi_home_esc}/g" \${NIFI_HOME}conf/state-management.xml
			sudo sed -i "s/=\.\//=\${nifi_home_esc}/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/\.\//\${nifi_home_esc}/g" \${NIFI_HOME}conf/authorizers.xml
			sudo sed -i "s/=\.\//=\${nifi_home_esc}/g" \${NIFI_HOME}conf/bootstrap.conf
			sudo runuser -l ${username} -c 'nifi set-single-user-credentials ${username} ${password}'
			xmlstarlet ed --delete '/loginIdentityProviders/provider[identifier = "single-user-provider"]' \${NIFI_HOME}conf/login-identity-providers.xml
			sudo sed -i "s/^nifi.security.user.authorizer=.*/nifi.security.user.authorizer=managed-authorizer/g" \${NIFI_HOME}conf/nifi.properties
			sudo sed -i "s/^nifi.security.user.login.identity.provider=/#nifi.security.user.login.identity.provider=/g" \${NIFI_HOME}conf/nifi.properties
		EOF
		)"
	fi
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "creating a system unit file for nifi..."
for host in ${nodes[@]}; do
	hostid=$(get node-id ${host})
	if [[ ${host} != ${registry_host} ]]; then
		if (( ${hostid} <= 3 )); then
			command="$(cat <<-EOF
				if [ -f "/etc/systemd/system/nifi.service" ]; then
					sudo rm /etc/systemd/system/nifi.service
				fi
				echo "[Unit]" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Description=Apache NiFi" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Requires=zookeeper.service" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "After=zookeeper.service" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "[Service]" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Type=forking" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "User=${username}" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Group=${username}" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "WorkingDirectory=\${NIFI_HOME}" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "ExecStart=nifi start" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "ExecStop=nifi stop" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "ExecRestart=nifi restart" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Restart=on-abnormal" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "[Install]" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "WantedBy=multi-user.target" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
			EOF
			)"
		else
			command="$(cat <<-EOF
				if [ -f "/etc/systemd/system/nifi.service" ]; then
					sudo rm /etc/systemd/system/nifi.service
				fi
				echo "[Unit]" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Description=Apache NiFi" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "[Service]" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Type=forking" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "User=${username}" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Group=${username}" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "WorkingDirectory=\${NIFI_HOME}" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "ExecStart=nifi start" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "ExecStop=nifi stop" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "ExecRestart=nifi restart" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "Restart=on-abnormal" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "[Install]" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "WantedBy=multi-user.target" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
				echo "" | sudo tee -a /etc/systemd/system/nifi.service > /dev/null
			EOF
			)"
		fi
	fi
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

echo "installing avro and postgres components for python3..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			sudo apt-get update
			sudo apt-get install libpq-dev python-dev
			sudo apt-get install -y python3-avro
			sudo apt-get install python3-pip
			sudo runuser -l ${username} -c 'python3 -m pip install avro'
			sudo runuser -l ${username} -c 'python3 -m pip install psycopg2'
			sudo chmod 755 /home/${username}/.local/lib/python3.9/site-packages/
		EOF
		)"
		remote="${installer}@$(get node ${host})"
		echo "ssh -t ${remote} \"${command}\""
		ssh -t ${remote} "${command}"
	fi
done

echo "starting nifi and enabling the managed services..."
for host in ${nodes[@]}; do
	if [[ ${host} != ${registry_host} ]]; then
		command="$(cat <<-EOF
			sudo systemctl daemon-reload
			sudo systemctl enable nifi
			sudo systemctl start nifi
		EOF
		)"
	else
		command="$(cat <<-EOF
			sudo systemctl daemon-reload
			sudo systemctl enable nifi-registry
			sudo systemctl start nifi-registry
		EOF
		)"
	fi
	remote="${installer}@$(get node ${host})"
	echo "ssh -t ${remote} \"${command}\""
	ssh -t ${remote} "${command}"
done

#<<'###BLOCK-TBD'
###BLOCK-TBD