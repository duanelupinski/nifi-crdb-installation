
variable "ssh_key_name" {}

variable "instance_defaults" {
  description = "Default settings to be used for each instance"
  type        = object({
    instance_name    = string
    instance_user    = string
    adapter_settings = object({
      type           = string
      host_interface = string
    })
    postgres_image   = string
    postgres_cpus    = number
    postgres_memory  = string
    workload_image   = string
    workload_cpus    = number
    workload_memory  = string
  })
  default     = {
    instance_name    = "postgres-small"
	instance_user    = "debian"
    adapter_settings = {
      type           = "bridged"
      host_interface = "eno3"
    }
	postgres_image   = "/mnt/vbox/postgres-small-image.box"
    postgres_cpus    = 2
    postgres_memory  = "4096 mib"
	workload_image   = "/mnt/vbox/workload-image.box"
    workload_cpus    = 2
    workload_memory  = "4096 mib"
  }
}
