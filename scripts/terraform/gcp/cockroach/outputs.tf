output "ssh_commands" {
  value = { for k, v in module.cluster: k =>
    format("ssh -i %s %s@%s", var.ssh_key_name, var.vm_user, v.public_ip)
  }
}

output "database_map" {
  value = { for k, v in module.cluster: k => {
    address      = v.public_ip
    workload     = v.workload_ip
    nodes        = [v.node1_ip, v.node2_ip, v.node3_ip]
    cpus         = -1
    memory       = -1
    concurrency  = 1
  }}
}
