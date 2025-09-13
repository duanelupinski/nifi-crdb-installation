locals {
  cloud_init_path = abspath("${path.module}/${var.cloud_init_file}")
}

resource "null_resource" "vm" {
  triggers = {
    name       = var.name
    cpus       = tostring(var.cpus)
    memory     = var.memory
    disk       = var.disk
    image      = var.image
    cloud_hash = filesha256(local.cloud_init_path)
  }

  # Create VM
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      if multipass info ${self.triggers.name} >/dev/null 2>&1; then
        echo "Instance '${self.triggers.name}' already exists, skipping launch."
        exit 0
      fi
      multipass launch ${self.triggers.image} \
        --name ${self.triggers.name} \
        --cpus ${self.triggers.cpus} \
        --mem ${self.triggers.memory} \
        --disk ${self.triggers.disk} \
        --cloud-init "${local.cloud_init_path}"
      echo "Launched ${self.triggers.name}"
    EOT
    interpreter = ["/bin/bash", "-lc"]
  }

  # Destroy VM
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -euo pipefail
      if multipass info ${self.triggers.name} >/dev/null 2>&1; then
        multipass delete ${self.triggers.name} || true
        multipass purge || true
        echo "Deleted ${self.triggers.name}"
      else
        echo "Instance '${self.triggers.name}' not found; nothing to delete."
      fi
    EOT
    interpreter = ["/bin/bash", "-lc"]
  }
}

# Grab the instance IP for outputs
data "external" "vm_ip" {
  depends_on = [null_resource.vm]
  program    = ["/bin/bash", "-lc", <<-EOT
    set -uo pipefail
    if multipass info ${var.name} >/dev/null 2>&1; then
      IP=$(multipass info ${var.name} | awk '/IPv4/ {print $2; exit}')
      printf '{"ip":"%s"}' "$IP"
    else
      # return an empty IP rather than failing
      printf '{"ip":""}'
    fi
  EOT
  ]
}
