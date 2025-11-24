output "vm_ip" {
  description = "Multipass VM IPv4"
  value       = try(data.external.vm_ip.result.ip, "")
}

output "mongo_uri" {
  description = "MongoDB URI (replica set enabled for Change Streams)"
  value       = "mongodb://${try(data.external.vm_ip.result.ip, "127.0.0.1")}:27017/?replicaSet=rs0"
}
