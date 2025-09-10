module "cluster" {
  source            = "./cluster"
  name_prefix       = var.name_prefix
  cpus              = var.cpus
  memory            = var.memory
  disk              = var.disk
  image             = var.image
  ssh_pubkey_path   = var.ssh_pubkey_path
  flowfile_dir      = var.flowfile_dir
  content_dirs      = var.content_dirs
  provenance_dirs   = var.provenance_dirs
  default_disk_size = var.default_disk_size
}
