output "instance_names" {
  value = module.cluster.instance_names
}

# Convenience: ssh commands
output "ssh_commands" {
  value = [
    for i, name in module.cluster.instance_names :
    "ssh -o StrictHostKeyChecking=no ubuntu@${name}"
  ]
}

output "repo_mounts" {
  value = module.cluster.repo_mounts
}
