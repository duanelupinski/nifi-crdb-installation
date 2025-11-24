output "cluster_cpus" {
  description = "The number of cpus available across all cockroach instances"
  value = virtualbox_vm.node1.cpus * 3
}

output "instance_memory" {
  description = "The amount of memory available on a single cockroach instance"
  value = virtualbox_vm.node1.memory
}

output "node1_ip" {
  description = "The virtual IP address assigned to the node1 instance"
  value = virtualbox_vm.node1.network_adapter.0.ipv4_address
}

output "node2_ip" {
  description = "The virtual IP address assigned to the node2 instance"
  value = virtualbox_vm.node2.network_adapter.0.ipv4_address
}

output "node3_ip" {
  description = "The virtual IP address assigned to the node3 instance"
  value = virtualbox_vm.node3.network_adapter.0.ipv4_address
}

output "proxy_ip" {
  description = "The virtual IP address assigned to the proxy instance"
  value = virtualbox_vm.proxy.network_adapter.0.ipv4_address
}

output "workload_ip" {
  description = "The virtual IP address assigned to the workload instance"
  value = virtualbox_vm.workload.network_adapter.0.ipv4_address
}
