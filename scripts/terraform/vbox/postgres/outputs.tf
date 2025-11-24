output "database_map" {
  value = { for k, v in module.instance: k => {
    address      = v.node_ip
    workload     = v.workload_ip
    nodes        = [v.node_ip]
    cpus         = v.instance_cpus
    memory       = v.instance_memory
    concurrency  = 1
  }}
}