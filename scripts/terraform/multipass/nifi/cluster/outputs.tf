output "instance_names" {
  value = [
    multipass_instance.node01.name,
    multipass_instance.node02.name,
    multipass_instance.node03.name,
    multipass_instance.registry.name
  ]
}

locals {
  flowfile_dir    = format("%s%d", var.disk_mount_prefix, 1)
  database_dir    = format("%s%d", var.disk_mount_prefix, 2)
  content_dirs    = [for i in range(var.content_count)     : format("%s%d", var.disk_mount_prefix, i + 3)]
  provenance_dirs = [for i in range(var.provenance_count)  : format("%s%d", var.disk_mount_prefix, i + 3 + var.content_count)]
}

output "repo_mounts" {
  description = "NiFi repository mount directories"
  value = {
    flowfile_dir    = local.flowfile_dir
    database_dir    = local.database_dir
    content_dirs    = local.content_dirs
    provenance_dirs = local.provenance_dirs
  }
}
