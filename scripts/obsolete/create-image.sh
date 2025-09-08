#!/bin/bash

PROG="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
BASE_IMAGE=""
LINUX_DISTRIBUTION="debian"
HOSTNAME=""
HOST_IP=""
USER_ID="${USER}"
SSH_PUB_KEY_FILE=""
META_DATA_FILE="meta-data"
USER_DATA_FILE="user-data"
NETWORK_INTERFACES_FILE=""
POST_CONFIG_INTERFACES_FILE=""
POST_CONFIG_STORAGES_FILE=""
POST_CONFIG_RESOURCES_FILE=""
AUTO_START="true"
VMS_FOLDER_LOCATION="${HOME}/VirtualBox VMs"
VBOXMANAGE=`which vboxmanage`
if [ -z "$VBOXMANAGE" ]; then
  VBOXMANAGE=`which vboxmanage.exe`
fi
GENISOIMAGE=`which genisoimage`
SED=`which sed`
UUIDGEN=`which uuidgen`
POSTCONFIGUREINTERFACES=${SCRIPT_DIR}/post-config-interfaces.sh
POSTCONFIGURESTORAGES=${SCRIPT_DIR}/post-config-storages.sh
POSTCONFIGURERESOURCES=${SCRIPT_DIR}/post-config-resources.sh

usage() {
  echo -e "USAGE: ${PROG} [--base-image <BASE_IMAGE>] [--linux-distribution LINUX_DISTRIBUTION]
        [--hostname <HOSTNAME>] [--host-ip <HOST_IP>] [--user-id <USER_ID>]
		[--ssh-pub-keyfile <SSH_PUB_KEY_FILE>]
		[--meta-data <META_DATA_FILE>] [--user-data <USER_DATA_FILE>]
		[--network-interfaces <NETWORK_INTERFACES_FILE>]
        [--post-config-interfaces POST_CONFIG_INTERFACES_FILE]
        [--post-config-storages POST_CONFIG_STORAGES_FILE]
        [--post-config-resources POST_CONFIG_RESOURCES_FILE]
        [--auto-start true|false] [--vms-folder VMS_FOLDER_LOCATION]\n"
}

help_exit() {
  usage
  echo "This is a utility script for create image using cloud-init.
Options:
  -b, --base-image BASE_IMAGE
              Name of VirtualBox base image.
  -l, --linux-distribution LINUX_DISTRIBUTION (debian|ubuntu)
              Name of Linux distribution. Default is '${LINUX_DISTRIBUTION}'.
  -o, --hostname HOSTNAME
              Hostname of new image
  -p, --host-ip HOST_IP
              Static IP address for the new image
  -d, --user-id USER_ID
              ID of user for SSH import.
  -k, --ssh-pub-keyfile SSH_PUB_KEY_FILE
              Path to an SSH public key.
  -m, --meta-data META_DATA_FILE
              Path to an meta data file. Default is '${META_DATA_FILE}'.
  -u, --user-data USER_DATA_FILE
              Path to an user data file. Default is '${USER_DATA_FILE}'.
  -n, --network-interfaces NETWORK_INTERFACES_FILE
              Path to an network interface data file.
  -i, --post-config-interfaces POST_CONFIG_INTERFACES_FILE
              Path to an post config interface data file.
  -s, --post-config-storages POST_CONFIG_STORAGES_FILE
              Path to an post config storage data file.
  -r, --post-config-resources POST_CONFIG_RESOURCES_FILE
              Path to an post config resources data file.
  -a, --auto-start true|false
              Auto start vm. Default is true.
  -f, --vms-folder VMS_FOLDER_LOCATION
              Path to location where VM files are stored.
  -h, --help  Output this help message.
"
  exit 0
}

assign() {
  key="${1}"
  value="${key#*=}"
  if [[ "${value}" != "${key}" ]]; then
    # key was of the form 'key=value'
    echo "${value}"
    return 0
  elif [[ "x${2}" != "x" ]]; then
    echo "${2}"
    return 2
  else
    output "Required parameter for '-${key}' not specified.\n"
    usage
    exit 1
  fi
  keypos=$keylen
}

while [[ $# -ge 1 ]]; do
  key="${1}"

  case $key in
    -*)
    keylen=${#key}
    keypos=1
    while [[ $keypos -lt $keylen ]]; do
      case ${key:${keypos}} in
        b|-base-image)
        BASE_IMAGE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        l|-linux-distribution)
        LINUX_DISTRIBUTION=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;        
        o|-hostname)
        HOSTNAME=$(assign "${key:${keypos}}" "${2}")
        HOSTNAME=`echo ${HOSTNAME} | tr '[:upper:]' '[:lower:]'`
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;      
        p|-host-ip)
        HOST_IP=$(assign "${key:${keypos}}" "${2}")
        HOST_IP=`echo ${HOST_IP} | tr '[:upper:]' '[:lower:]'`
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        d|-user-id)
        USER_ID=$(assign "${key:${keypos}}" "${2}")
        USER_ID=`echo ${USER_ID} | tr '[:upper:]' '[:lower:]'`
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        k|-ssh-pub-keyfile)
        SSH_PUB_KEY_FILE=$(assign "${key:${keypos}}" "${2}")
        SSH_PUB_KEY_FILE_CONTENT=`cat ${SSH_PUB_KEY_FILE}`
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        m|-meta-data)
        META_DATA_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        u|-user-data)
        USER_DATA_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        n|-network-interfaces)
        NETWORK_INTERFACES_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        i|-post-config-interfaces)
        POST_CONFIG_INTERFACES_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        s|-post-config-storages)
        POST_CONFIG_STORAGES_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        r|-post-config-resources)
        POST_CONFIG_RESOURCES_FILE=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        a|-auto-start)
        AUTO_START=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        f|-vms-folder)
        VMS_FOLDER_LOCATION=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        h*|-help)
        help_exit
        ;;
        *)
        output "Unknown option '${key:${keypos}}'.\n"
        usage
        exit 1
        ;;
      esac
      ((keypos++))
    done
    ;;
  esac
  shift
done

META_DATA_FILE=${SCRIPT_DIR}/data/${LINUX_DISTRIBUTION}/${META_DATA_FILE}
USER_DATA_FILE=${SCRIPT_DIR}/data/${LINUX_DISTRIBUTION}/${USER_DATA_FILE}
NETWORK_INTERFACES_FILE=${SCRIPT_DIR}/data/${LINUX_DISTRIBUTION}/${NETWORK_INTERFACES_FILE}
POST_CONFIG_INTERFACES_FILE=${SCRIPT_DIR}/data/${LINUX_DISTRIBUTION}/${POST_CONFIG_INTERFACES_FILE}
POST_CONFIG_STORAGES_FILE=${SCRIPT_DIR}/data/${LINUX_DISTRIBUTION}/${POST_CONFIG_STORAGES_FILE}
POST_CONFIG_RESOURCES_FILE=${SCRIPT_DIR}/data/${LINUX_DISTRIBUTION}/${POST_CONFIG_RESOURCES_FILE}

if [[ -z ${BASE_IMAGE} ]]; then
  echo "Base image ${BASE_IMAGE} not found"
  exit 1
fi

if [[ -z ${HOSTNAME} ]]; then
  echo "Hostname not set"
  exit 1
fi

if [[ -z ${HOST_IP} ]]; then
  echo "Host IP not set"
  exit 1
fi

if [[ -z ${USER_ID} ]]; then
  echo "User ID not set"
  exit 1
fi

if [[ -z ${SSH_PUB_KEY_FILE} || ! -f ${SSH_PUB_KEY_FILE} ]]; then
  echo "SSH public key File ${SSH_PUB_KEY_FILE} not found!"
  exit 1
fi

if [[ -z ${META_DATA_FILE} || ! -f ${META_DATA_FILE} ]]; then
  echo "Meta data File ${META_DATA_FILE} not found!"
  exit 1
fi

if [[ -z ${USER_DATA_FILE} || ! -f ${USER_DATA_FILE} ]]; then
  echo "User data File ${USER_DATA_FILE} not found!"
  exit 1
fi

mkdir -p vms/${HOSTNAME}

UUID=`${UUIDGEN}`

FILES="vms/${HOSTNAME}/user-data vms/${HOSTNAME}/meta-data"

${SED} -e "s|#HOSTNAME#|${HOSTNAME}|g" -e "s|#UUID#|${UUID}|g" ${META_DATA_FILE} > vms/${HOSTNAME}/meta-data
${SED} -e "s|#USER-ID#|${USER_ID}|g" -e "s|#SSH-PUB-KEY#|${SSH_PUB_KEY_FILE_CONTENT}|g" -e "s|#HOSTNAME#|${HOSTNAME}|g" ${USER_DATA_FILE} > vms/${HOSTNAME}/user-data

if [[ -f ${NETWORK_INTERFACES_FILE} ]]; then
  ${SED} -e "s|#HOSTNAME#|${HOSTNAME}|g" -e "s|#UUID#|${UUID}|g" -e "s|#HOST-IP#|${HOST_IP}|g" ${NETWORK_INTERFACES_FILE} > vms/${HOSTNAME}/network-config
  FILES="vms/${HOSTNAME}/user-data vms/${HOSTNAME}/meta-data vms/${HOSTNAME}/network-config"
fi

${GENISOIMAGE} -input-charset utf-8 \
  -output vms/${HOSTNAME}/${HOSTNAME}-cidata.iso \
  -volid cidata -joliet -rock ${FILES}

mkdir -p "${VMS_FOLDER_LOCATION}/${HOSTNAME}/"
mv vms/${HOSTNAME}/* "${VMS_FOLDER_LOCATION}/${HOSTNAME}/."
"${VBOXMANAGE}" clonevm ${BASE_IMAGE} --mode all --name ${HOSTNAME} --register

medium="${VMS_FOLDER_LOCATION}/${HOSTNAME}/${HOSTNAME}-cidata.iso"
if [[ ${VBOXMANAGE} == *exe ]]; then
  medium="${medium////\\}"
  medium="${medium//\\mnt\\c/C:}"
  medium="${medium//\\mnt\\d/D:}"
fi
"${VBOXMANAGE}" storageattach ${HOSTNAME} --storagectl "IDE Controller" --port 1 --device 0 --type dvddrive --medium "${medium}"

if [[ -f ${POST_CONFIG_INTERFACES_FILE} ]]; then
  ${SED} -e "s|#HOSTONLYIF#|\"${hostonlyif}\"|g" ${POST_CONFIG_INTERFACES_FILE} > ${SCRIPT_DIR}/../../.private/${HOSTNAME}-post-config-interfaces
  ${POSTCONFIGUREINTERFACES} -v ${HOSTNAME} -i ${SCRIPT_DIR}/../../.private/${HOSTNAME}-post-config-interfaces
fi

if [[ -f ${POST_CONFIG_STORAGES_FILE} ]]; then
  ${POSTCONFIGURESTORAGES} -v ${HOSTNAME} -s ${POST_CONFIG_STORAGES_FILE} -f "${VMS_FOLDER_LOCATION}"
fi

if [[ -f ${POST_CONFIG_RESOURCES_FILE} ]]; then
  ${POSTCONFIGURERESOURCES} -v ${HOSTNAME} -r ${POST_CONFIG_RESOURCES_FILE}
fi

if [[ "${AUTO_START}" = "true" ]]; then
  "${VBOXMANAGE}" startvm ${HOSTNAME} --type headless
fi
