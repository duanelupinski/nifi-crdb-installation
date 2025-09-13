### Required ###

variable "cluster_name" {
  type        = string
  description = "unique name used to identify nodes in this cluster"
}

variable "public_key_name" {
  type = string
  description = "Public key name for our cluster"
}

### Optional ###

variable "cluster_user" {
  type        = string
  default     = "debian"
  description = "user account used to connect with nodes in this cluster"
}

variable "network_adapter_settings" {
  description = "Default network adapter settings for each VBox instance"
  type        = object({
    type           = string
    host_interface = string
  })
  default     = {
    type           = "bridged"
    host_interface = "eno3"
  }
}

variable "cockroach_image" {
  type        = string
  default     = "/mnt/vbox/cockroach-small-image.box"
  description = "VBox instance image for the cockroach nodes"
}

variable "cockroach_cpus" {
  type        = number
  default     = 2
  description = "number of CPUs per VBox instance for the cockroach nodes"
}

variable "cockroach_memory" {
  type        = string
  default     = "4096 mib"
  description = "VBox instance memory size for the cockroach nodes"
}

variable "proxy_image" {
  type        = string
  default     = "/mnt/vbox/ha-proxy-image.box"
  description = "VBox instance image for the proxy node"
}

variable "proxy_cpus" {
  type        = number
  default     = 2
  description = "number of CPUs per VBox instance for the proxy node"
}

variable "proxy_memory" {
  type        = string
  default     = "4096 mib"
  description = "VBox instance memory size for the proxy node"
}

variable "workload_image" {
  type        = string
  default     = "/mnt/vbox/workload-image.box"
  description = "VBox instance image for the workload node"
}

variable "workload_cpus" {
  type        = number
  default     = 2
  description = "number of CPUs per VBox instance for the workload node"
}

variable "workload_memory" {
  type        = string
  default     = "4096 mib"
  description = "VBox instance memory size for the workload node"
}
