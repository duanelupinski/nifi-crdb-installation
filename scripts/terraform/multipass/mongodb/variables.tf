variable "name" {
  description = "Multipass instance name"
  type        = string
  default     = "mongo-dev"
}

variable "cpus" {
  description = "vCPUs for the VM"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory for the VM (e.g., 2G, 4096M)"
  type        = string
  default     = "2G"
}

variable "disk" {
  description = "Disk size for the VM (e.g., 10G)"
  type        = string
  default     = "10G"
}

variable "image" {
  description = "Multipass base image"
  type        = string
  default     = "22.04" # Ubuntu Jammy
}

variable "admin_user" {
  description = "Initial MongoDB admin username."
  type        = string
  default     = "admin_user"
}

variable "admin_pass" {
  description = "Initial MongoDB admin password."
  type        = string
  default     = "Change_Default_Password123!"
  sensitive   = true
}

variable "cert_base_dir" {
  description = "Absolute path to the certs folder"
  type        = string
}
