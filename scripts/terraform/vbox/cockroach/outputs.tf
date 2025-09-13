output "database_map" {
  value = { for k, v in module.cluster: k => {
    address      = v.proxy_ip
    workload     = v.workload_ip
    nodes        = [v.node1_ip, v.node2_ip, v.node3_ip]
    cpus         = v.cluster_cpus
    memory       = v.instance_memory
    concurrency  = 1
  }}
}
