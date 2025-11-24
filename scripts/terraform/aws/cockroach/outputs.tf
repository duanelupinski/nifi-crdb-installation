output "ssh_commands" {
  value = { for k, v in module.cluster: k =>
    format("ssh -i %s %s@%s", var.ssh_key_name, var.vm_user, v.public_dns)
  }
}

output "database_map" {
  value = { for k, v in module.cluster: k => {
    address      = v.public_dns
    workload     = v.workload_dns
    nodes        = [v.node1_dns, v.node2_dns, v.node3_dns]
    cpus         = -1
    memory       = -1
    concurrency  = 1
  }}
}
