variable "name_prefix" {
  type    = string
  default = "nifi"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = string
  default = "4G" # Multipass uses strings for sizes
}

variable "disk" {
  type    = string
  default = "100G"
}

variable "image" {
  type    = string
  default = "24.04" # Ubuntu 24.04 LTS (arm64 on Apple Silicon)
}

variable "ssh_pubkey_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "content_count" {
  description = "Number of content disks per NiFi node"
  type        = number
  default     = 3
}

variable "provenance_count" {
  description = "Number of provenance disks per NiFi node"
  type        = number
  default     = 2
}

variable "disk_mount_prefix" {
  description = "Base mount path for loop disks"
  type        = string
  default     = "/mnt/disk"
}
