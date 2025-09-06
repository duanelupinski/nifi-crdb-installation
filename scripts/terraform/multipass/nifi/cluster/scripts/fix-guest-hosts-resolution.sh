#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

VM_NAME="${1:?usage: $0 <vm-name>}"

multipass exec "$VM_NAME" -- sudo bash -lc '
  set -o errexit -o nounset -o pipefail

  # 1) /etc/hosts hygiene
  chown root:root /etc/hosts
  chmod 644 /etc/hosts
  sed -i "s/\r$//" /etc/hosts || true

  # 2) Make NSS consult /etc/hosts before DNS
  if [ -f /etc/nsswitch.conf ]; then
    cp /etc/nsswitch.conf /etc/nsswitch.conf.bak
    awk '"'"'
      BEGIN{fixed=0}
      /^hosts:/{ print "hosts: files dns myhostname"; fixed=1; next }
      {print}
      END{ if(!fixed){ print "hosts: files dns myhostname" } }
    '"'"' /etc/nsswitch.conf.bak > /tmp/nsswitch.new
    mv /tmp/nsswitch.new /etc/nsswitch.conf
  fi

  # 3) Smoke tests (don’t fail the build if ping fails once)
  which getent >/dev/null 2>&1 && getent hosts nifi-node-01 || true
  which getent >/dev/null 2>&1 && getent hosts nifi-node-02 || true
  which getent >/dev/null 2>&1 && getent hosts nifi-node-03 || true
  which getent >/dev/null 2>&1 && getent hosts nifi-registry || true
'
echo "Updated NSS and hosts on ${VM_NAME}"
