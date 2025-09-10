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
  default = "50G"
}

variable "image" {
  type    = string
  default = "24.04" # Ubuntu 24.04 LTS (arm64 on Apple Silicon)
}

variable "ssh_pubkey_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "flowfile_dir" {
  type = string
  default = "/mnt/flowfile-repo:20G"
}

variable "content_dirs" {
  type = list(string)
  default = ["/mnt/cont-repo1","/mnt/cont-repo2","/mnt/cont-repo3"]
}

variable "provenance_dirs" {
  type = list(string)
  default = ["/mnt/prov-repo1","/mnt/prov-repo2"]
}

variable "default_disk_size" {
  type = string
  default = "50G"
}
