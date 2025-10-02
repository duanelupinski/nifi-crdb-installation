#####################
# Paths & file loads
#####################
locals {
  default_cert_base_dir = abspath("${path.root}/../../../../.private/pgbouncer-certs")

  cert_base_dir = length(trimspace(var.cert_base_dir)) > 0 ? abspath(var.cert_base_dir) : local.default_cert_base_dir

  srv_dir = "${local.cert_base_dir}/${var.name}"

  # Read files if they exist; otherwise empty string
  ca_crt = try(file("${local.cert_base_dir}/_ca/ca.crt"), "")
  ca_key = try(file("${local.cert_base_dir}/_ca/ca.key"), "")
  ca_srl = try(file("${local.cert_base_dir}/_ca/ca.srl"), "")

  srv_cnf = try(file("${local.srv_dir}/pgbouncer.cnf"), "")
  srv_crt = try(file("${local.srv_dir}/pgbouncer.crt"), "")
  srv_csr = try(file("${local.srv_dir}/pgbouncer.csr"), "")
  srv_key = try(file("${local.srv_dir}/pgbouncer.key"), "")
  srv_pem = try(file("${local.srv_dir}/pgbouncer.pem"), "")

  default_root_cert = abspath("${path.root}/../../../../.private/pgbouncer-certs/root.crt")
  root_cert_file = length(trimspace(var.crdb_root_cert)) > 0 ? abspath(var.crdb_root_cert) : local.default_root_cert
  root_crt = try(file("${local.root_cert_file}"), "")

  cloud_init_payload = templatefile("${path.module}/cloud-init/pgbouncer-vm.tpl.yaml", {
    vm_name     = var.name
    admin_user  = var.admin_user
    admin_pass  = var.admin_pass
    crdb_host   = var.crdb_hostname
    crdb_port   = var.crdb_port
    crdb_db     = var.crdb_database
    cr_crt_b64  = base64encode(local.root_crt)

    ca_crt_b64  = base64encode(local.ca_crt)
    ca_key_b64  = base64encode(local.ca_key)
    ca_srl_b64  = base64encode(local.ca_srl)

    srv_cnf_b64 = base64encode(local.srv_cnf)
    srv_crt_b64 = base64encode(local.srv_crt)
    srv_csr_b64 = base64encode(local.srv_csr)
    srv_key_b64 = base64encode(local.srv_key)
    srv_pem_b64 = base64encode(local.srv_pem)
  })

  cloud_init_outdir = "${path.module}/cloud-init/.rendered"
  cloud_init_file   = "${local.cloud_init_outdir}/${var.name}-cloud-init.yaml"

  # Trigger hash of the actual payload string (no need to read a file)
  cloud_payload_sha = sha256(local.cloud_init_payload)
}

#####################
# Materialize the cloud-init to disk (Multipass needs a file path)
#####################
resource "null_resource" "render_cloud_init" {
  triggers = {
    payload_sha = local.cloud_payload_sha
    out_path    = local.cloud_init_file
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      mkdir -p "${local.cloud_init_outdir}"
      cat > "${local.cloud_init_file}" <<'EOF'
${local.cloud_init_payload}
EOF
      echo "Wrote ${local.cloud_init_file}"
    EOT
    interpreter = ["/bin/bash", "-lc"]
  }
}

#####################
# Create / Destroy VM via Multipass CLI
#####################
resource "null_resource" "vm" {
  triggers = {
    name          = var.name
    cpus          = tostring(var.cpus)
    memory        = var.memory
    disk          = var.disk
    image         = var.image
    payload_sha   = local.cloud_payload_sha   # re-run create step if payload changes
    cloudinitpath = local.cloud_init_file
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
        --cloud-init "${self.triggers.cloudinitpath}"
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

  depends_on = [null_resource.render_cloud_init]
}

#####################
# Grab the instance IP for outputs
#####################
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
