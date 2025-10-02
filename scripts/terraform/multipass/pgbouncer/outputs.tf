output "vm_ip" {
  description = "Multipass VM IPv4"
  value       = try(data.external.vm_ip.result.ip, "")
}
