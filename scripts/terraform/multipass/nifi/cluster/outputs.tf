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
    flowfile_dir    = split(":", var.flowfile_dir)[0]
    content_dirs    = [for s in var.content_dirs : trimspace(split(":", s)[0])]
    provenance_dirs = [for s in var.provenance_dirs : trimspace(split(":", s)[0])]
  }
}
