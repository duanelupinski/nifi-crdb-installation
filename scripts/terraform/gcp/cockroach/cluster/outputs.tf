output "instance_id" {
  value = google_compute_instance.proxy.instance_id
}

output "public_ip" {
  description = "The public IP address assigned to the cluster, if applicable."
  value = google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip
}

output "node1_ip" {
  description = "The public IP address assigned to the node1 instance, if applicable."
  value = google_compute_instance.node1.network_interface.0.access_config.0.nat_ip
}

output "node2_ip" {
  description = "The public IP address assigned to the node2 instance, if applicable."
  value = google_compute_instance.node2.network_interface.0.access_config.0.nat_ip
}

output "node3_ip" {
  description = "The public IP address assigned to the node3 instance, if applicable."
  value = google_compute_instance.node3.network_interface.0.access_config.0.nat_ip
}

output "proxy_ip" {
  description = "The public IP address assigned to the proxy instance, if applicable."
  value = google_compute_instance.proxy.network_interface.0.access_config.0.nat_ip
}

output "workload_ip" {
  description = "The public IP address assigned to the workload instance, if applicable."
  value = google_compute_instance.workload.network_interface.0.access_config.0.nat_ip
}
