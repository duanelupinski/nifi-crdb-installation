#!/bin/bash

PROG="$(basename "${0}")"
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
VMNAME=""
POST_CONFIG_STORAGES_FILE=""
VMS_FOLDER_LOCATION="${HOME}/VirtualBox VMs"
VBOXMANAGE=`which vboxmanage`
if [ -z "$VBOXMANAGE" ]; then
  VBOXMANAGE=`which vboxmanage.exe`
fi

usage() {
  echo -e "USAGE: ${PROG} [--vm-name <VMNAME>] [--vms-folder VMS_FOLDER_LOCATION]\n"
}

help_exit() {
  usage
  echo "This is a utility script for post configure vm.
Options:
  -v, --vm-name VMNAME
              Name of VistualBox vm.
  -s, --post-config-storages POST_CONFIG_STORAGES_FILE
              Path to an post config storages data file.
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
        v|-vm-name)
        VMNAME=$(assign "${key:${keypos}}" "${2}")
        if [[ $? -eq 2 ]]; then shift; fi
        keypos=$keylen
        ;;
        s|-post-config-storages)
        POST_CONFIG_STORAGES_FILE=$(assign "${key:${keypos}}" "${2}")
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

if [[ -z ${VMNAME} ]]; then
  echo "VM name not found"
  exit 1
fi

if [[ -z ${POST_CONFIG_STORAGES_FILE} || ! -f ${POST_CONFIG_STORAGES_FILE} ]]; then
  echo "Post config storages data file, not found"
  exit 1
fi

STORAGES=`cat ${POST_CONFIG_STORAGES_FILE} | shyaml keys`

for storage in ${STORAGES}; do
  ID=`cat ${POST_CONFIG_STORAGES_FILE} | shyaml get-value $storage.id`
  SIZE=`cat ${POST_CONFIG_STORAGES_FILE} | shyaml get-value $storage.size`
  FORMAT=`cat ${POST_CONFIG_STORAGES_FILE} | shyaml get-value $storage.format`
  VARIANT=`cat ${POST_CONFIG_STORAGES_FILE} | shyaml get-value $storage.variant`
  EXTENSION=`echo ${FORMAT} | tr '[:upper:]' '[:lower:]'`

  medium="${VMS_FOLDER_LOCATION}/${VMNAME}/disks/${VMNAME}-disk-${ID}.${EXTENSION}"
  if [[ ${VBOXMANAGE} == *exe ]]; then
    medium="${medium////\\}"
    medium="${medium//\\mnt\\c/C:}"
    medium="${medium//\\mnt\\d/D:}"
  fi
  "${VBOXMANAGE}" createmedium disk --size ${SIZE} --format ${FORMAT} --variant ${VARIANT} --filename "${medium}"
  "${VBOXMANAGE}" storageattach ${VMNAME} --storagectl "SATA Controller" --port ${ID} --type hdd --medium "${medium}"
done
