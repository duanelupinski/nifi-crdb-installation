locals {
  node01 = "${var.name_prefix}-node-01"
  node02 = "${var.name_prefix}-node-02"
  node03 = "${var.name_prefix}-node-03"
  reg    = "${var.name_prefix}-registry"

  content_arg    = "--content ${join(",", var.content_dirs)}"
  provenance_arg = "--provenance ${join(",", var.provenance_dirs)}"
  flowfile_arg   = "--flowfile ${var.flowfile_dir}"
  database_arg   = "--database ${var.database_dir}"
}

# ---------- Instances ----------
resource "multipass_instance" "node01" {
  name           = local.node01
  cpus           = var.cpus
  memory         = var.memory
  disk           = "400G" # was 100G; large enough for 7×50G loop files
  image          = var.image
  cloudinit_file = "${path.module}/cloud-init/nifi-node.yaml"
}

resource "multipass_instance" "node02" {
  name           = local.node02
  cpus           = var.cpus
  memory         = var.memory
  disk           = "400G" # was 100G; large enough for 7×50G loop files
  image          = var.image
  cloudinit_file = "${path.module}/cloud-init/nifi-node.yaml"
}

resource "multipass_instance" "node03" {
  name           = local.node03
  cpus           = var.cpus
  memory         = var.memory
  disk           = "400G" # was 100G; large enough for 7×50G loop files
  image          = var.image
  cloudinit_file = "${path.module}/cloud-init/nifi-node.yaml"
}

resource "multipass_instance" "registry" {
  name           = local.reg
  cpus           = var.cpus
  memory         = var.memory
  disk           = var.disk
  image          = var.image
  cloudinit_file = "${path.module}/cloud-init/registry-node.yaml"
}

# ---------- Node 01 Provisoners ----------

# Post-creation steps for node01:
# 1) wait for cloud-init boot-finished
# 2) set hostname + persist + /etc/hosts entry
resource "terraform_data" "node01_post" {
  # Make sure we run after the instance exists
  depends_on = [multipass_instance.node01]

  # Re-run the whole chain if either the instance name or the desired static IP changes
  triggers_replace = [
    multipass_instance.node01.name
  ]

  # ---- 1) wait for cloud-init to finish (boot-finished file) ----
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NAME="${multipass_instance.node01.name}"

      # Wait until the guest is reachable
      for i in $(seq 1 60); do
        if multipass exec "$NAME" -- true >/dev/null 2>&1; then
          break
        fi
        sleep 5
      done

      # Wait up to 10 minutes for cloud-init to complete
      for i in $(seq 1 120); do
        if multipass exec "$NAME" -- test -f /var/lib/cloud/instance/boot-finished; then
          exit 0
        fi
        sleep 5
      done

      echo "cloud-init did not finish in time for $NAME" >&2
      exit 1
    EOT
  }

  # ---- 2) set hostname + persist + /etc/hosts mapping ----
  provisioner "local-exec" {
    command = <<-EOT
      set -o errexit -o nounset -o pipefail
      NAME="${multipass_instance.node01.name}"

      multipass exec "$NAME" -- sudo bash -lc " \
        hostnamectl set-hostname '${local.node01}.nifi.demo' && \
        printf '%s\n' '${local.node01}.nifi.demo' > /etc/hostname && \
        mkdir -p /etc/cloud/cloud.cfg.d && \
        printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99_preserve_hostname.cfg && \
        (grep -q '${local.node01}.nifi.demo' /etc/hosts || \
         echo '127.0.1.1 ${local.node01}.nifi.demo ${local.node01}' >> /etc/hosts) \
      "
    EOT
  }
}

resource "null_resource" "fix_hosts_node01" {
  depends_on = [
    multipass_instance.node01,
    terraform_data.node01_post,
    null_resource.hosts_on_mac,
    null_resource.publish_ssh_and_config
  ]
  triggers   = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/wait-ssh.sh -u ubuntu -t 600 -c ${local.node01} && ${path.module}/scripts/fix-guest-hosts-resolution.sh ${local.node01}"
  }
}

# Create and mount 5 loop-backed ext4 filesystems for node01
resource "null_resource" "node01_loop_disks" {
  depends_on = [multipass_instance.node01]

  # re-run on each apply so /etc/fstab stays correct if you change COUNT/SIZE
  triggers = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/prepare-loop-disks.sh ${local.node01} --default-size ${var.default_disk_size} ${local.flowfile_arg} ${local.database_arg} ${local.content_arg} ${local.provenance_arg}"
  }
}

# ---------- Node 02 Provisoners ----------

# Post-creation steps for node02:
# 1) wait for cloud-init boot-finished
# 2) set hostname + persist + /etc/hosts entry
resource "terraform_data" "node02_post" {
  # Make sure we run after the instance exists
  depends_on = [multipass_instance.node02]

  # Re-run the whole chain if either the instance name or the desired static IP changes
  triggers_replace = [
    multipass_instance.node02.name
  ]

  # ---- 1) wait for cloud-init to finish (boot-finished file) ----
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NAME="${multipass_instance.node02.name}"

      # Wait until the guest is reachable
      for i in $(seq 1 60); do
        if multipass exec "$NAME" -- true >/dev/null 2>&1; then
          break
        fi
        sleep 5
      done

      # Wait up to 10 minutes for cloud-init to complete
      for i in $(seq 1 120); do
        if multipass exec "$NAME" -- test -f /var/lib/cloud/instance/boot-finished; then
          exit 0
        fi
        sleep 5
      done

      echo "cloud-init did not finish in time for $NAME" >&2
      exit 1
    EOT
  }

  # ---- 2) set hostname + persist + /etc/hosts mapping ----
  provisioner "local-exec" {
    command = <<-EOT
      set -o errexit -o nounset -o pipefail
      NAME="${multipass_instance.node02.name}"

      multipass exec "$NAME" -- sudo bash -lc " \
        hostnamectl set-hostname '${local.node02}.nifi.demo' && \
        printf '%s\n' '${local.node02}.nifi.demo' > /etc/hostname && \
        mkdir -p /etc/cloud/cloud.cfg.d && \
        printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99_preserve_hostname.cfg && \
        (grep -q '${local.node02}.nifi.demo' /etc/hosts || \
         echo '127.0.1.1 ${local.node02}.nifi.demo ${local.node02}' >> /etc/hosts) \
      "
    EOT
  }
}

resource "null_resource" "fix_hosts_node02" {
  depends_on = [
    null_resource.fix_hosts_node01,
    multipass_instance.node02,
    terraform_data.node02_post,
    null_resource.hosts_on_mac,
    null_resource.publish_ssh_and_config
  ]
  triggers   = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/wait-ssh.sh -u ubuntu -t 600 -c ${local.node02} && ${path.module}/scripts/fix-guest-hosts-resolution.sh ${local.node02}"
  }
}

# Create and mount 5 loop-backed ext4 filesystems for node02
resource "null_resource" "node02_loop_disks" {
  depends_on = [multipass_instance.node02]

  # re-run on each apply so /etc/fstab stays correct if you change COUNT/SIZE
  triggers = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/prepare-loop-disks.sh ${local.node02} --default-size ${var.default_disk_size} ${local.flowfile_arg} ${local.database_arg} ${local.content_arg} ${local.provenance_arg}"
  }
}

# ---------- Node 03 Provisoners ----------

# Post-creation steps for node03:
# 1) wait for cloud-init boot-finished
# 2) set hostname + persist + /etc/hosts entry
resource "terraform_data" "node03_post" {
  # Make sure we run after the instance exists
  depends_on = [multipass_instance.node03]

  # Re-run the whole chain if either the instance name or the desired static IP changes
  triggers_replace = [
    multipass_instance.node03.name
  ]

  # ---- 1) wait for cloud-init to finish (boot-finished file) ----
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NAME="${multipass_instance.node03.name}"

      # Wait until the guest is reachable
      for i in $(seq 1 60); do
        if multipass exec "$NAME" -- true >/dev/null 2>&1; then
          break
        fi
        sleep 5
      done

      # Wait up to 10 minutes for cloud-init to complete
      for i in $(seq 1 120); do
        if multipass exec "$NAME" -- test -f /var/lib/cloud/instance/boot-finished; then
          exit 0
        fi
        sleep 5
      done

      echo "cloud-init did not finish in time for $NAME" >&2
      exit 1
    EOT
  }

  # ---- 2) set hostname + persist + /etc/hosts mapping ----
  provisioner "local-exec" {
    command = <<-EOT
      set -o errexit -o nounset -o pipefail
      NAME="${multipass_instance.node03.name}"

      multipass exec "$NAME" -- sudo bash -lc " \
        hostnamectl set-hostname '${local.node03}.nifi.demo' && \
        printf '%s\n' '${local.node03}.nifi.demo' > /etc/hostname && \
        mkdir -p /etc/cloud/cloud.cfg.d && \
        printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99_preserve_hostname.cfg && \
        (grep -q '${local.node03}.nifi.demo' /etc/hosts || \
         echo '127.0.1.1 ${local.node03}.nifi.demo ${local.node03}' >> /etc/hosts) \
      "
    EOT
  }
}

resource "null_resource" "fix_hosts_node03" {
  depends_on = [
    null_resource.fix_hosts_node02,
    multipass_instance.node03,
    terraform_data.node03_post,
    null_resource.hosts_on_mac,
    null_resource.publish_ssh_and_config
  ]
  triggers   = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/wait-ssh.sh -u ubuntu -t 600 -c ${local.node03} && ${path.module}/scripts/fix-guest-hosts-resolution.sh ${local.node03}"
  }
}

# Create and mount 5 loop-backed ext4 filesystems for node03
resource "null_resource" "node03_loop_disks" {
  depends_on = [multipass_instance.node03]

  # re-run on each apply so /etc/fstab stays correct if you change COUNT/SIZE
  triggers = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/prepare-loop-disks.sh ${local.node03} --default-size ${var.default_disk_size} ${local.flowfile_arg} ${local.database_arg} ${local.content_arg} ${local.provenance_arg}"
  }
}

# ---------- Registry Provisoners ----------

# Post-creation steps for registry:
# 1) wait for cloud-init boot-finished
# 2) set hostname + persist + /etc/hosts entry
resource "terraform_data" "registry_post" {
  # Make sure we run after the instance exists
  depends_on = [multipass_instance.registry]

  # Re-run the whole chain if either the instance name or the desired static IP changes
  triggers_replace = [
    multipass_instance.registry.name
  ]

  # ---- 1) wait for cloud-init to finish (boot-finished file) ----
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NAME="${multipass_instance.registry.name}"

      # Wait until the guest is reachable
      for i in $(seq 1 60); do
        if multipass exec "$NAME" -- true >/dev/null 2>&1; then
          break
        fi
        sleep 5
      done

      # Wait up to 10 minutes for cloud-init to complete
      for i in $(seq 1 120); do
        if multipass exec "$NAME" -- test -f /var/lib/cloud/instance/boot-finished; then
          exit 0
        fi
        sleep 5
      done

      echo "cloud-init did not finish in time for $NAME" >&2
      exit 1
    EOT
  }

  # ---- 2) set hostname + persist + /etc/hosts mapping ----
  provisioner "local-exec" {
    command = <<-EOT
      set -o errexit -o nounset -o pipefail
      NAME="${multipass_instance.registry.name}"

      multipass exec "$NAME" -- sudo bash -lc " \
        hostnamectl set-hostname 'nifi-registry.nifi.demo' && \
        printf '%s\n' 'nifi-registry.nifi.demo' > /etc/hostname && \
        mkdir -p /etc/cloud/cloud.cfg.d && \
        printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99_preserve_hostname.cfg && \
        (grep -q 'nifi-registry.nifi.demo' /etc/hosts || \
         echo '127.0.1.1 nifi-registry.nifi.demo nifi-registry' >> /etc/hosts) \
      "
    EOT
  }
}

resource "null_resource" "fix_hosts_registry" {
  depends_on = [
    multipass_instance.registry,
    terraform_data.registry_post,
    null_resource.hosts_on_mac,
    null_resource.publish_ssh_and_config
  ]
  triggers   = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/wait-ssh.sh -u ubuntu -t 600 -c nifi-registry && ${path.module}/scripts/fix-guest-hosts-resolution.sh nifi-registry"
  }
}

# ---------- Cluster Provisoners ----------

# Writes/refreshes one block in your Mac's /etc/hosts for all present VMs.
resource "null_resource" "hosts_on_mac" {
  depends_on = [
    multipass_instance.node01,
    multipass_instance.node02,
    multipass_instance.node03,
    multipass_instance.registry,
  ]
  triggers = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "${path.module}/scripts/update-hosts-on-mac.sh"
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -o errexit -o nounset -o pipefail
      BEGIN='# BEGIN multipass-nifi'; END='# END multipass-nifi'
      TMP="$(mktemp)"
      awk -v b="$BEGIN" -v e="$END" '
        $0==b {inblk=1; next}
        $0==e {inblk=0; next}
        !inblk {print}
      ' /etc/hosts > "$TMP"
      sudo mv "$TMP" /etc/hosts
      echo "Removed multipass-nifi block from /etc/hosts"
    EOT
  }
}

# Teach all VMs in the cluster to resolve each other by hostname.
resource "null_resource" "cluster_hosts_on_vms" {
  depends_on = [
    multipass_instance.node01,
    multipass_instance.node02,
    multipass_instance.node03,
    multipass_instance.registry,
  ]
  triggers   = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "cluster/scripts/cluster-hosts-on-vms.sh apply"
  }
}

# Publish your Mac's SSH pubkey to all present VMs and write ~/.ssh/config entries
resource "null_resource" "publish_ssh_and_config" {
  depends_on = [
    null_resource.cluster_hosts_on_vms,
    multipass_instance.node01,
    multipass_instance.node02,
    multipass_instance.node03,
    multipass_instance.registry,
  ]

  # Re-run each apply (IPs can change on DHCP)
  triggers = { always = timestamp() }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    # Change the pubkey path here if you use a different key
    command     = "${path.module}/scripts/publish-ssh-key-and-config.sh ${var.ssh_pubkey_path}"
  }
}
