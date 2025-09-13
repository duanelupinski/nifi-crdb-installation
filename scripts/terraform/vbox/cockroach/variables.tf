
variable "ssh_key_name" {}

variable "cluster_defaults" {
  description = "Default settings to be used for each cluster"
  type        = object({
    cluster_name     = string
    cluster_user     = string
    adapter_settings = object({
      type           = string
      host_interface = string
    })
    cockroach_image  = string
    cockroach_cpus   = number
    cockroach_memory = string
    proxy_image      = string
    proxy_cpus       = number
    proxy_memory     = string
    workload_image   = string
    workload_cpus    = number
    workload_memory  = string
  })
  default     = {
    cluster_name     = "cockroach-small"
    cluster_user     = "debian"
    adapter_settings = {
      type           = "bridged"
      host_interface = "eno3"
    }
    cockroach_image  = "/mnt/vbox/cockroach-small-image.box"
    cockroach_cpus   = 2
    cockroach_memory = "4096 mib"
    proxy_image      = "/mnt/vbox/ha-proxy-image.box"
    proxy_cpus       = 2
    proxy_memory     = "4096 mib"
    workload_image   = "/mnt/vbox/workload-image.box"
    workload_cpus    = 2
    workload_memory  = "4096 mib"
  }
}
