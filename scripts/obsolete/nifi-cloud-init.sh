#!/bin/bash

## A POSIX variable - reset in case getopts has been used previously in the shell.
OPTIND=1
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
VMS_FOLDER_LOCATION="${HOME}/VirtualBox VMs"
BASE_IP="192.168.1.60"
VBOXMANAGE=`which vboxmanage`
if [ -z "$VBOXMANAGE" ]; then
  VBOXMANAGE=`which vboxmanage.exe`
fi

## contsants to define steps in the process so that all or one can be executed
INIT_ENV=1
INSTALL=2
SCALE=3
JOIN=4
REPLACE=5
REJOIN=6
UPGRADE=7
MAX_STEPS=7

## set default values for all parameters
help=false
start=0
end=0
num=0
off=0
config=""
prefix=""
auto=true
bridged=false
registry=true
memory="6g"
authority=""

## read input parameters for this execution
while getopts "h?s:e:n:o:c:p:a:f:i:br:m:A:" opt; do
  case "${opt}" in
    h|\?) help=true;;
    # ignore any value provided for end, will only execute one step at a time
    s) start=$OPTARG
       end=$OPTARG;;
    n) num=$OPTARG;;
    o) off=$OPTARG;;
    c) config=$OPTARG;;
    p) prefix=$OPTARG;;
    a) auto=$OPTARG;;
    f) VMS_FOLDER_LOCATION=$OPTARG;;
    i) BASE_IP=$OPTARG;;
    b) bridged=true;;
    r) registry=$OPTARG;;
    m) memory=$OPTARG;;
    A) authority=$OPTARG;;
  esac
done

## if help needed then print the menu and exit
if [ $help = true ]; then
  echo
  echo "usage: $0 -h|? [Show Help = false] -s [Start = 0] -e [End = 0] -n [Num Instances = 0] -o [Offset Instances = 0] -c [Config = \"\"] -p [Prefix = \"\"] -a [Auto Deploy = true] -f [VMS Folder Location = ${HOME}/VirtualBox\ VMs] -i [Base IP = \"192.168.1.60\"] -b [Bridged Network = false] -r [Registry = true] -m [Memory = 6g] -A <Certificate Authority>"
  echo
  echo "This script is designed to create the image files required for a NiFi cluster dev environment leveraging pre-defined cloud-init scripts"
  echo
  echo "SWITCH PARAMETERS:"
  echo "-h|? Show Help:  if provided then prints this menu"
  echo "-s   Start:      execute starting at the step indicated, defaults to do nothing"
  echo "-e   End:        end execution at the step indicated, defaults to do nothing"
  echo "-n   Num:        number of instances to create for the step indicated, defaults to 3"
  echo "-o   Offset:     number of instances assumed to exist that should not be created, defaults to 0"
  echo "-c   Config:     include a nested folder for a VM configuration, i.e. 'pc/', if you have custom config files in the data file path for the node type"
  echo "-p   Prefix:     if included prepend the prefix to the node name. i.e. with 'pc-' the busybox node would be named pc-busybox"
  echo "-a   Auto:       indicate if the vbox image should be auto deployed in the local environment, defaults to true"
  echo "-f   Folder:     location where VM files are stored for VirtualBox, defaults to ${HOME}/VirtualBox\ VMs"
  echo "-i   Base IP:    the initial sddress to start from when assiging static IPs for the virtual machines, defaults to '192.168.1.60'"
  echo "-b   Bridged:    if provided then this NiFi uses a bridged network, otherwise assumes a host-only network, defaults to false"
  echo "-r   Registry:   if provided then this NiFi will include a node for the registry, defaults to true"
  echo "-m   Memory:     specifies the amount of memory to allocate to the NiFi service, defaults to 6g"
  echo "-A   Authority:  specifies the certificate authority used for certificate signing requests"
  echo
  exit 0
else 
  ## check parameter values to confim options used
  valid=true
  if [[ ${start} -lt ${INIT_ENV} || ${end} -gt ${MAX_STEPS} || ${end} -lt ${start} ]]; then
    echo "ERROR: one or both of the steps start ${start} and end ${end} are not valid"
    valid=false
  fi
  if [[ ${start} -le ${JOIN} && ${end} -ge ${JOIN} ]]; then
    if [[ -z "${authority}" ]]; then
      echo "ERROR: certificate authority not provided"
      valid=false
    fi
  fi
  if [ $valid = false ]; then
    echo "exiting script due to validation errors"
    exit 1
  fi
  if [[ ${start} -eq ${end} ]]; then
    echo "executing only step ${start} of the process with ${num} instances"
  else
    echo "executing all steps starting at ${start} and continuing through step ${end}"
  fi
fi

for (( step = ${start}; step <= ${end}; step++ ))
do
  echo "Step ${step})"
  case "${step}" in
    ${INIT_ENV})
      echo "installing the base packages and defining the host-only network interface"
      sudo apt install -y openssh-client
      ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa <<<n
      sudo apt-get install -y python3-pip
      sudo pip3 install shyaml
      sudo apt-get install -y genisoimage
      sudo apt-get install -y uuid-runtime
      if [[ ${VBOXMANAGE} == *exe ]]; then
        echo "Preparing VirtualBox environment for Windows"
        # there's no limit on the host setting for Windows so below config is not needed
        #sudo /bin/sh -c "echo '* 192.168.0.0/16 0:0:0:0:0:0:0:0/16' >> /etc/vbox/networks.conf"
      else
        echo "Preparing VirtualBox environment for Linux"
        ip_range='* 192.168.0.0/16 0:0:0:0:0:0:0:0/16'
        if ! grep -xq '${ip_range}' /etc/vbox/networks.conf; then 
          sudo /bin/sh -c "echo '${ip_range}' >> /etc/vbox/networks.conf"
        fi
      fi
      hostonlyif=$("${VBOXMANAGE}" list hostonlyifs | head -n 1 | awk '{split($0,a,":"); print a[2]}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      if [ -z "${hostonlyif}" ]; then
        hostonlyif=$("${VBOXMANAGE}" hostonlyif create | cut -d "'" -f 2)
      fi
      mkdir -p ${SCRIPT_DIR}/../../.private
      echo -n ${hostonlyif} > ${SCRIPT_DIR}/../../.private/hostonlyif
      "${VBOXMANAGE}" hostonlyif ipconfig "${hostonlyif}" --ip 192.168.56.1 --netmask 255.255.0.0
      ;;
    ${INSTALL})
      adapter="-hostonly"
      if [ $bridged = true ]; then
        adapter="-bridged"
      else
        export hostonlyif=$(cat ${SCRIPT_DIR}/../../.private/hostonlyif)
      fi
      if [ $registry = true ]; then
        echo "creating the nifi registry node for workflow version control"
        ${SCRIPT_DIR}/create-image.sh \
          -k ~/.ssh/id_rsa.pub \
          -u registry/${config}user-data \
          -n registry/${config}network-config \
          -i registry/${config}post-config-interfaces${adapter} \
          -r registry/${config}post-config-resources \
          -o ${prefix}registry \
          -p ${BASE_IP} \
          -l debian \
          -b debian-base-image \
          -a ${auto} \
          -f "${VMS_FOLDER_LOCATION}"
      fi
      echo "creating the nifi nodes for running integration pipelines"
      if [[ ${num} -eq 0 ]]; then
        num=3
      fi
      nodes=""
      declare -A machine
      for ((i=1; i<=${num}; i++ )); do
        id=$((${i}+${off}))
        host=${prefix}nifi-node${id}
        ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
        nodes="${nodes}node-${id}:${host}=${ip} "
        machine[${host}]=${ip}
      done
      for m in "${!machine[@]}"; do
        ${SCRIPT_DIR}/create-image.sh \
          -k ~/.ssh/id_rsa.pub \
          -u nifi/${config}user-data \
          -n nifi/${config}network-config \
          -i nifi/${config}post-config-interfaces${adapter} \
          -r nifi/${config}post-config-resources \
          -s nifi/${config}post-config-storages \
          -o ${m} \
          -p ${machine[$m]} \
          -l debian \
          -b debian-base-image \
          -a ${auto} \
          -f "${VMS_FOLDER_LOCATION}"
      done
      echo "waiting a few minutes to give time for cloud-init to initialize..."
      sleep 180
      if [ $registry = true ]; then
        echo "checking readiness for host ${prefix}registry, which may take some time..."
        ssh-keygen -f ~/.ssh/known_hosts -R "${BASE_IP}"
        result=""
        while true; do
          result=$(ssh -t -oStrictHostKeyChecking=no debian@${BASE_IP} "cloud-init status --wait")
          sleep 5
          if [[ ${result} == *"status: done"* ]]; then
            break
          fi
        done
        echo "host ${prefix}registry is ready!!"
      fi
      for m in "${!machine[@]}"; do
        echo "checking readiness for host ${m}, which may take some time..."
        ssh-keygen -f ~/.ssh/known_hosts -R "${machine[$m]}"
        result=""
        while true; do
          result=$(ssh -t -oStrictHostKeyChecking=no debian@${machine[$m]} "cloud-init status --wait")
          sleep 5
          if [[ ${result} == *"status: done"* ]]; then
            break
          fi
        done
        echo "host ${m} is ready!!"
      done
      if [ $registry = true ]; then
        ${SCRIPT_DIR}/nifi-installation.sh -S \
          -M ${memory} \
          -r registry=${BASE_IP} \
          ${nodes} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-installation.out
      else
        ${SCRIPT_DIR}/nifi-installation.sh -S \
          -M ${memory} \
          ${nodes} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-installation.out
      fi
      ;;
    ${SCALE})
      adapter="-hostonly"
      if [ $bridged = true ]; then
        adapter="-bridged"
      else
        export hostonlyif=$(cat ${SCRIPT_DIR}/../../.private/hostonlyif)
      fi
      if [[ ${num} -eq 0 ]]; then
        num=3
      fi
      declare -A machine
      for ((i=1; i<=${num}; i++ )); do
        id=$((${i}+${off}))
        host=${prefix}nifi-node${id}
        ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
        machine[${host}]=${ip}
      done
      for m in "${!machine[@]}"; do
        ${SCRIPT_DIR}/create-image.sh \
          -k ~/.ssh/id_rsa.pub \
          -u nifi/${config}user-data \
          -n nifi/${config}network-config \
          -i nifi/${config}post-config-interfaces${adapter} \
          -r nifi/${config}post-config-resources \
          -s nifi/${config}post-config-storages \
          -o ${m} \
          -p ${machine[$m]} \
          -l debian \
          -b debian-base-image \
          -a ${auto} \
          -f "${VMS_FOLDER_LOCATION}"
      done
      echo "waiting a few minutes to give time for cloud-init to initialize..."
      sleep 180
      for m in "${!machine[@]}"; do
        echo "checking readiness for host ${m}, which may take some time..."
        ssh-keygen -f ~/.ssh/known_hosts -R "${machine[$m]}"
        result=""
        while true; do
          result=$(ssh -t -oStrictHostKeyChecking=no debian@${machine[$m]} "cloud-init status --wait")
          sleep 5
          if [[ ${result} == *"status: done"* ]]; then
            break
          fi
        done
        echo "host ${m} is ready!!"
      done
      ;;
    ${JOIN})
      existing=""
      for ((i=1; i<=${off}; i++ )); do
        id=${i}
        host=${prefix}nifi-node${id}
        ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
        existing="${existing}existing-${id}:${host}=${ip} "
      done
      if [[ ${num} -eq 0 ]]; then
        num=3
      fi
      newnodes=""
      for ((i=1; i<=${num}; i++ )); do
        id=$((${i}+${off}))
        host=${prefix}nifi-node${id}
        ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
        newnodes="${newnodes}node-${id}:${host}=${ip} "
      done
      if [ $registry = true ]; then
        ${SCRIPT_DIR}/nifi-scaleup.sh -S \
          -M ${memory} \
          -r registry=${BASE_IP} \
          -A ${authority} \
          ${existing} \
          ${newnodes} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-scaleup.out
      else
        ${SCRIPT_DIR}/nifi-scaleup.sh -S \
          -M ${memory} \
          -A ${authority} \
          ${existing} \
          ${newnodes} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-scaleup.out
      fi
      ;;
    ${REPLACE})
      adapter="-hostonly"
      if [ $bridged = true ]; then
        adapter="-bridged"
      else
        export hostonlyif=$(cat ${SCRIPT_DIR}/../../.private/hostonlyif)
      fi
      if [[ ${off} -eq 0 ]]; then
        echo "ERROR: specify which machine number to replace using the -o comand line option, i.e. -o 3"
        exit 1
      fi
      declare -A machine
      id=${off}
      host=${prefix}nifi-node${id}
      ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
      machine[${host}]=${ip}
      for m in "${!machine[@]}"; do
        ${SCRIPT_DIR}/create-image.sh \
          -k ~/.ssh/id_rsa.pub \
          -u nifi/${config}user-data \
          -n nifi/${config}network-config \
          -i nifi/${config}post-config-interfaces${adapter} \
          -r nifi/${config}post-config-resources \
          -s nifi/${config}post-config-storages \
          -o ${m} \
          -p ${machine[$m]} \
          -l debian \
          -b debian-base-image \
          -a ${auto} \
          -f "${VMS_FOLDER_LOCATION}"
      done
      echo "waiting a few minutes to give time for cloud-init to initialize..."
      sleep 180
      for m in "${!machine[@]}"; do
        echo "checking readiness for host ${m}, which may take some time..."
        ssh-keygen -f ~/.ssh/known_hosts -R "${machine[$m]}"
        result=""
        while true; do
          result=$(ssh -t -oStrictHostKeyChecking=no debian@${machine[$m]} "cloud-init status --wait")
          sleep 5
          if [[ ${result} == *"status: done"* ]]; then
            break
          fi
        done
        echo "host ${m} is ready!!"
      done
      ;;
    ${REJOIN})
      if [[ ${off} -eq 0 ]]; then
        echo "ERROR: specify which machine number to replace using the -o comand line option, i.e. -o 3"
        exit 1
      fi
      if [[ ${num} -eq 0 ]]; then
        echo "ERROR: specify the number of machines in the cluster using the -n comand line option, i.e. -n 3"
        exit 1
      fi
      existing=""
      for ((i=1; i<=${num}; i++ )); do
        if ! [ $i = $off ]; then
          id=${i}
          host=${prefix}nifi-node${id}
          ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
          existing="${existing}existing-${id}:${host}=${ip} "
        fi 
      done
      id=${off}
      host=${prefix}nifi-node${id}
      ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
      replacing="node-${id}:${host}=${ip}"
      if [ $registry = true ]; then
        ${SCRIPT_DIR}/nifi-replace.sh -S \
          -M ${memory} \
          -r registry=${BASE_IP} \
          -A ${authority} \
          ${existing} \
          ${replacing} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-replace.out
      else
        ${SCRIPT_DIR}/nifi-replace.sh -S \
          -M ${memory} \
          -A ${authority} \
          ${existing} \
          ${replacing} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-replace.out
      fi
      ;;
    ${UPGRADE})
      if [[ ${num} -eq 0 ]]; then
        echo "ERROR: specify the number of machines in the cluster using the -n comand line option, i.e. -n 3"
        exit 1
      fi
      nodes=""
      for ((i=1; i<=${num}; i++ )); do
        id=${i}
        host=${prefix}nifi-node${id}
        ip=${BASE_IP%.*}.$((${BASE_IP//*.}+${id}))
        nodes="${nodes}node-${id}:${host}=${ip} "
      done
      if [ $registry = true ]; then
        ${SCRIPT_DIR}/nifi-upgrade.sh -S \
          -M ${memory} \
          -r registry=${BASE_IP} \
          ${nodes} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-upgrade.out
      else
        ${SCRIPT_DIR}/nifi-upgrade.sh -S \
          -M ${memory} \
          ${nodes} \
          contrepo-contS1R1:cont-repo1=/dev/sdb1 \
          contrepo-contS1R2:cont-repo2=/dev/sdc1 \
          contrepo-contS1R3:cont-repo3=/dev/sdd1 \
          provrepo-provS1R1:prov-repo1=/dev/sde1 \
          provrepo-provS1R2:prov-repo2=/dev/sdf1 \
          2>&1 | tee ${SCRIPT_DIR}/../../.private/nifi-upgrade.out
      fi
      ;;
  esac
done