module "cluster" {
  source            = "./cluster"
  name_prefix       = var.name_prefix
  cpus              = var.cpus
  memory            = var.memory
  disk              = var.disk
  image             = var.image
  ssh_pubkey_path   = var.ssh_pubkey_path
  content_count     = var.content_count
  provenance_count  = var.provenance_count
  disk_mount_prefix = var.disk_mount_prefix
}
