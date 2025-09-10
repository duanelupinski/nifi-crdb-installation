output "instance_names" {
  value = [
    multipass_instance.node01.name,
    multipass_instance.node02.name,
    multipass_instance.node03.name,
    multipass_instance.registry.name
  ]
}

output "repo_mounts" {
  description = "NiFi repository mount directories"
  value = {
    flowfile_dir    = var.flowfile_dir
    database_dir    = var.database_dir
    content_dirs    = var.content_dirs
    provenance_dirs = var.provenance_dirs
  }
}
